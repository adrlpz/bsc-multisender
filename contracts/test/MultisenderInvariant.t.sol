// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Multisender} from "../src/Multisender.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// =============================================================================
// MultisenderInvariant.t.sol
//
// Foundry stateful-fuzz / invariant suite for v1.1.1.
//
// foundry.toml ships with `fuzz.runs = 256`. The default invariant config
// inherits this, giving us 256 outer runs × 256 inner calls per run = 65 536
// state transitions exercised against a single Multisender deployment.
//
// Invariants (must hold after EVERY transition):
//   I1. address(multisender).balance == 0
//       (transit-only: every successful multisendBNB pays out exactly msg.value;
//        no other path can deposit BNB; failed paths revert atomically.)
//   I2. multisender.feeBps() <= MAX_FEE_BPS
//   I3. multisender.feeReceiver() != address(0)
//   I4. multisender.owner() != address(0)
//   I5. token.balanceOf(address(multisender)) == 0  (transit-only for ERC20s)
//
// =============================================================================

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Handler is the only contract the invariant runner targets. It wraps every
///      Multisender entrypoint with bounded, well-formed inputs so the fuzzer
///      explores reachable states (not pathological reverts every call).
contract Handler is Test {
    Multisender public immutable multisender;
    MockERC20 public immutable token;

    address public currentOwner;        // tracks the actual owner across transferOwnership/acceptOwnership
    address public pendingOwnerSlot;    // mirror for acceptOwnership routing
    address public immutable ownerA;
    address public immutable ownerB;
    address[] public userPool;

    // Stats — useful for `forge test --invariant -vvv` post-mortems.
    uint256 public callsMultisendBNB;
    uint256 public callsMultisendToken;
    uint256 public callsSetFee;
    uint256 public callsSetReceiver;
    uint256 public callsQueueRescue;
    uint256 public callsRescueToken;
    uint256 public callsRescueBNB;
    uint256 public callsTransferOwnership;
    uint256 public callsAcceptOwnership;

    constructor(Multisender _ms, MockERC20 _tok, address _ownerA, address _ownerB) {
        multisender = _ms;
        token = _tok;
        ownerA = _ownerA;
        ownerB = _ownerB;
        currentOwner = _ownerA;

        // Seed a pool of users to act as senders / recipients.
        for (uint160 i = 1; i <= 16; i++) {
            userPool.push(address(uint160(0x1000) + i));
        }
    }

    // ---------------------------------------------------------------
    // BNB multisend
    // ---------------------------------------------------------------
    function multisendBNB(uint8 nSeed, uint64 amtSeed) external {
        uint256 n = bound(uint256(nSeed), 1, 5);
        uint256 each = bound(uint256(amtSeed), 1, 1 ether);
        uint256 total = n * each;

        address[] memory r = new address[](n);
        uint256[] memory a = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            r[i] = userPool[i % userPool.length];
            a[i] = each;
        }

        address sender = userPool[uint256(nSeed) % userPool.length];
        vm.deal(sender, total);
        vm.prank(sender);
        multisender.multisendBNB{value: total}(r, a);
        callsMultisendBNB++;
    }

    // ---------------------------------------------------------------
    // Token multisend
    // ---------------------------------------------------------------
    function multisendToken(uint8 nSeed, uint64 amtSeed, uint16 maxFeeSeed) external {
        uint256 n = bound(uint256(nSeed), 1, 5);
        uint256 each = bound(uint256(amtSeed), 1, 1_000 ether);
        uint256 total = n * each;
        // Allow up to MAX_FEE_BPS so the slippage check never spuriously reverts.
        uint16 maxFee = uint16(bound(uint256(maxFeeSeed), uint256(multisender.feeBps()), 100));

        address[] memory r = new address[](n);
        uint256[] memory a = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            r[i] = userPool[i % userPool.length];
            a[i] = each;
        }

        // Mint enough for total + max possible fee (fee = total * 100 / 10_000 = 1%).
        uint256 fee = (total * uint256(multisender.feeBps())) / 10_000;
        address sender = userPool[uint256(nSeed) % userPool.length];
        token.mint(sender, total + fee);
        vm.prank(sender);
        token.approve(address(multisender), total + fee);

        vm.prank(sender);
        multisender.multisendToken(address(token), r, a, maxFee);
        callsMultisendToken++;
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------
    function setFee(uint16 feeSeed) external {
        uint16 newFee = uint16(bound(uint256(feeSeed), 0, 100));
        vm.prank(currentOwner);
        multisender.setFee(newFee);
        callsSetFee++;
    }

    function setFeeReceiver(uint8 seed) external {
        // Always non-zero — pull from the user pool so I3 holds.
        address newRcv = userPool[uint256(seed) % userPool.length];
        vm.prank(currentOwner);
        multisender.setFeeReceiver(newRcv);
        callsSetReceiver++;
    }

    function queueRescue() external {
        if (multisender.rescueQueuedAt() != 0) return; // already queued — skip
        vm.prank(currentOwner);
        multisender.queueRescue();
        callsQueueRescue++;
    }

    function rescueToken(uint64 amtSeed) external {
        if (multisender.rescueQueuedAt() == 0) return;
        if (block.timestamp < multisender.rescueQueuedAt() + multisender.rescueDelay()) return;
        uint256 stuck = token.balanceOf(address(multisender));
        if (stuck == 0) {
            // Drain the queue so rescueDelay logic gets exercised; nothing to transfer.
            // Use 0 amount — safeTransfer(0) on a normal ERC20 succeeds.
            vm.prank(currentOwner);
            multisender.rescueToken(address(token), 0);
        } else {
            uint256 amt = bound(uint256(amtSeed), 1, stuck);
            vm.prank(currentOwner);
            multisender.rescueToken(address(token), amt);
        }
        callsRescueToken++;
    }

    function rescueBNB(uint64 amtSeed) external {
        if (multisender.rescueQueuedAt() == 0) return;
        if (block.timestamp < multisender.rescueQueuedAt() + multisender.rescueDelay()) return;
        uint256 bal = address(multisender).balance;
        // Note: under normal operation bal is always 0 (I1). This branch is a
        // no-op + queue reset, exercising the M3 path without violating I1.
        if (bal == 0) {
            // amount must be 0 to avoid InsufficientBNB.
            vm.prank(currentOwner);
            multisender.rescueBNB(0);
        } else {
            uint256 amt = bound(uint256(amtSeed), 0, bal);
            vm.prank(currentOwner);
            multisender.rescueBNB(amt);
        }
        callsRescueBNB++;
    }

    function transferOwnership(uint8 seed) external {
        // Flip between ownerA and ownerB so the invariant covers ownership churn.
        address candidate = (seed % 2 == 0) ? ownerA : ownerB;
        vm.prank(currentOwner);
        multisender.transferOwnership(candidate);
        pendingOwnerSlot = candidate;
        callsTransferOwnership++;
    }

    function acceptOwnership() external {
        address pending = multisender.pendingOwner();
        if (pending == address(0)) return;
        vm.prank(pending);
        multisender.acceptOwnership();
        currentOwner = pending;
        pendingOwnerSlot = address(0);
        callsAcceptOwnership++;
    }

    // Time advance helper so rescue paths actually unlock during long runs.
    function warp(uint16 secondsSeed) external {
        uint256 dt = bound(uint256(secondsSeed), 1, 25 hours);
        vm.warp(block.timestamp + dt);
    }
}

contract MultisenderInvariantTest is StdInvariant, Test {
    Multisender public multisender;
    MockERC20 public token;
    Handler public handler;

    address internal ownerA = address(0xA11CE);
    address internal ownerB = address(0xB0B);
    address internal feeReceiver0 = address(0xFEE);

    function setUp() public {
        multisender = new Multisender(ownerA, feeReceiver0, 0);
        token = new MockERC20();
        handler = new Handler(multisender, token, ownerA, ownerB);

        // Limit invariant fuzzer to the handler — Multisender entrypoints are
        // reached transitively with proper pranking, mints, and approvals.
        targetContract(address(handler));

        // Selector list: every handler entrypoint participates in the fuzz.
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.multisendBNB.selector;
        selectors[1] = handler.multisendToken.selector;
        selectors[2] = handler.setFee.selector;
        selectors[3] = handler.setFeeReceiver.selector;
        selectors[4] = handler.queueRescue.selector;
        selectors[5] = handler.rescueToken.selector;
        selectors[6] = handler.rescueBNB.selector;
        selectors[7] = handler.transferOwnership.selector;
        selectors[8] = handler.acceptOwnership.selector;
        selectors[9] = handler.warp.selector;
        selectors[10] = handler.multisendBNB.selector; // weight BNB path higher
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev I1: contract is transit-only for BNB.
    function invariant_contractHoldsNoBNB() public view {
        assertEq(address(multisender).balance, 0, "I1: contract holds BNB");
    }

    /// @dev I2: feeBps never exceeds the hard cap.
    function invariant_feeBpsBelowCap() public view {
        assertLe(multisender.feeBps(), multisender.MAX_FEE_BPS(), "I2: feeBps > MAX_FEE_BPS");
    }

    /// @dev I3: feeReceiver always non-zero.
    function invariant_feeReceiverNonZero() public view {
        assertTrue(multisender.feeReceiver() != address(0), "I3: feeReceiver is zero");
    }

    /// @dev I4: owner always non-zero (Ownable2Step prevents accidental renounce
    ///      to the zero address; renounceOwnership exists but the handler never
    ///      calls it).
    function invariant_ownerNonZero() public view {
        assertTrue(multisender.owner() != address(0), "I4: owner is zero");
    }

    /// @dev I5: token transit-only. Any stuck balance must be the result of a
    ///      direct transfer (which the handler never performs); otherwise rescue
    ///      handling kept the contract clean.
    function invariant_contractHoldsNoTokens() public view {
        assertEq(token.balanceOf(address(multisender)), 0, "I5: contract holds tokens");
    }

    /// @dev Lightweight call-distribution log so the fuzzer effort is visible.
    function invariant_callDistribution() public view {
        // Cumulative sanity — never strictly required for safety, but verifies
        // the handler did meaningful work. With 256x256 runs we expect each
        // bucket to be non-trivially exercised in aggregate.
        // (No assertion; just keep the symbol referenced so the compiler emits
        // the getter for `forge test -vvv` introspection.)
        handler.callsMultisendBNB();
    }
}
