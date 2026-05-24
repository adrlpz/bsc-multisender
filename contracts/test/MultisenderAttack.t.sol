// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Multisender} from "../src/Multisender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// =============================================================================
// MultisenderAttack.t.sol
//
// Adversarial test pass on top of the v1.1 unit tests. Each test exercises one
// concrete attacker pattern that a hostile actor could attempt against the live
// contract at 0xdE1Ca791fE17A8d4A1AC32dE32c74c02c1Ae2Cf0.
//
// Mapped to docs/AUDIT-V2.md sections.
// =============================================================================

/// @dev ERC777-style malicious token. After every `transferFrom`, hooks the
///      recipient via a callback that re-enters `multisendToken`. Used to
///      verify the `nonReentrant` guard.
contract MaliciousReentrantToken is ERC20 {
    address public hookTarget; // contract to call back into
    bytes public hookCalldata; // calldata to invoke
    bool public hookArmed;

    constructor() ERC20("Reenter", "RE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address target, bytes calldata data) external {
        hookTarget = target;
        hookCalldata = data;
        hookArmed = true;
    }

    function disarm() external {
        hookArmed = false;
    }

    /// @dev OZ ERC20 v5 single _update hook (post-transfer). Calls the target.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (hookArmed && from != address(0) && to != address(0)) {
            // Disarm before the call so the inner call doesn't loop forever
            // when the inner call itself triggers transfers.
            hookArmed = false;
            (bool ok, bytes memory ret) = hookTarget.call(hookCalldata);
            // Bubble up the inner revert so the test can assert on it.
            if (!ok) {
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
    }
}

/// @dev BNB recipient that re-enters `multisendBNB` from `receive()`.
contract ReentrantBNBRecipient {
    Multisender public immutable target;
    bool public hookArmed = true;
    address[] internal innerRecipients;
    uint256[] internal innerAmounts;

    constructor(Multisender _target) {
        target = _target;
        innerRecipients.push(address(0xBEEF));
        innerAmounts.push(1);
    }

    function disarm() external {
        hookArmed = false;
    }

    receive() external payable {
        if (!hookArmed) return;
        hookArmed = false; // one-shot
        // Re-enter — must revert with ReentrancyGuardReentrantCall.
        target.multisendBNB{value: 1}(innerRecipients, innerAmounts);
    }
}

/// @dev BNB recipient with a `receive()` that burns gas / always reverts.
contract GasGriefRecipient {
    bool public revertOnReceive;

    constructor(bool _revertOnReceive) {
        revertOnReceive = _revertOnReceive;
    }

    receive() external payable {
        if (revertOnReceive) revert("nope");
        // burn ~all forwarded gas
        for (uint256 i = 0; i < 1_000_000; i++) {
            assembly {
                pop(keccak256(0, 32))
            }
        }
    }
}

/// @dev Standard mintable ERC20.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MultisenderAttackTest is Test {
    Multisender internal sender;
    MockERC20 internal token;

    address internal owner = address(0xA11CE);
    address internal feeReceiver = address(0xFEE);
    address internal user = address(0xCAFE);

    function setUp() public {
        sender = new Multisender(owner, feeReceiver, 0);
        token = new MockERC20();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _singleRecipient(address to, uint256 amt)
        internal
        pure
        returns (address[] memory r, uint256[] memory a)
    {
        r = new address[](1);
        a = new uint256[](1);
        r[0] = to;
        a[0] = amt;
    }

    // =========================================================================
    // 1. Reentrancy via malicious ERC777-style token
    // =========================================================================
    /// @dev Attacker deploys a token whose `_update` hook re-enters
    ///      `multisendToken` mid-loop. The `nonReentrant` modifier MUST block
    ///      the inner call before any state can be observed in an inconsistent
    ///      window.
    function testAttack_reentrancyViaERC777Token() public {
        MaliciousReentrantToken evil = new MaliciousReentrantToken();
        evil.mint(user, 1_000 ether);

        vm.prank(user);
        evil.approve(address(sender), 1_000 ether);

        // Arm the hook to re-enter multisendToken with a tiny payload.
        (address[] memory r, uint256[] memory a) = _singleRecipient(address(0xBEEF), 1 ether);
        bytes memory innerCall = abi.encodeWithSelector(
            sender.multisendToken.selector,
            address(evil),
            r,
            a,
            uint16(0)
        );
        evil.arm(address(sender), innerCall);

        (address[] memory r2, uint256[] memory a2) = _singleRecipient(address(0xCAFE1), 100 ether);
        vm.prank(user);
        // OZ ReentrancyGuard v5 reverts with ReentrancyGuardReentrantCall().
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        sender.multisendToken(address(evil), r2, a2, 0);
    }

    /// @dev Sanity: with the hook DISARMED, the same flow succeeds. Ensures the
    ///      revert above came from the guard, not the token wiring.
    function testAttack_reentrancyHookDisarmed_succeeds() public {
        MaliciousReentrantToken evil = new MaliciousReentrantToken();
        evil.mint(user, 1_000 ether);

        vm.prank(user);
        evil.approve(address(sender), 1_000 ether);

        (address[] memory r, uint256[] memory a) = _singleRecipient(address(0xCAFE1), 100 ether);
        vm.prank(user);
        sender.multisendToken(address(evil), r, a, 0);
        assertEq(evil.balanceOf(address(0xCAFE1)), 100 ether);
    }

    // =========================================================================
    // 2. Reentrancy via malicious BNB recipient
    // =========================================================================
    /// @dev A recipient contract re-enters `multisendBNB` from `receive()`.
    ///      The whole outer tx must revert atomically.
    function testAttack_reentrancyViaBNBRecipient() public {
        ReentrantBNBRecipient evilRcv = new ReentrantBNBRecipient(sender);
        // The recipient needs balance to be able to send 1 wei when re-entering.
        vm.deal(address(evilRcv), 1 ether);

        (address[] memory r, uint256[] memory a) = _singleRecipient(address(evilRcv), 1 ether);

        vm.deal(user, 1 ether);
        vm.prank(user);
        // The outer call expects the BNB transfer to fail because the inner
        // re-entry reverts (ReentrancyGuard) which propagates out of `call`.
        // The contract wraps that as BNBTransferFailed.
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.BNBTransferFailed.selector, address(evilRcv))
        );
        sender.multisendBNB{value: 1 ether}(r, a);
    }

    // =========================================================================
    // 3. Out-of-gas / revert griefing via recipient
    // =========================================================================
    /// @dev A recipient that reverts in `receive()` causes the entire batch to
    ///      revert. No partial drain, no stuck state.
    function testAttack_recipientReverts_atomicRollback() public {
        GasGriefRecipient grief = new GasGriefRecipient(true); // always revert

        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](2);
        r[0] = address(0xBEEF);
        r[1] = address(grief);
        a[0] = 1 ether;
        a[1] = 1 ether;

        vm.deal(user, 2 ether);
        uint256 beefBefore = address(0xBEEF).balance;
        uint256 senderBalBefore = address(sender).balance;

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.BNBTransferFailed.selector, address(grief))
        );
        sender.multisendBNB{value: 2 ether}(r, a);

        // Atomicity: BEEF didn't get paid even though it's index 0.
        assertEq(address(0xBEEF).balance, beefBefore, "no partial drain");
        assertEq(address(sender).balance, senderBalBefore, "contract holds nothing");
        // Caller still has the funds.
        assertEq(user.balance, 2 ether);
    }

    /// @dev Recipient that burns gas in `receive()`. Forge default tx gas is
    ///      large; we forward all gas via `call{value:}("")`. Either the burn
    ///      completes (transfer succeeds) or it OOGs and the whole tx reverts.
    ///      Either way: no partial state.
    function testAttack_recipientGasBurn_atomic() public {
        GasGriefRecipient grief = new GasGriefRecipient(false); // burns gas, doesn't revert

        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](2);
        r[0] = address(0xBEEF);
        r[1] = address(grief);
        a[0] = 1 ether;
        a[1] = 1 ether;

        vm.deal(user, 2 ether);
        // Cap gas tightly so the burn loop OOGs.
        vm.prank(user);
        try sender.multisendBNB{value: 2 ether, gas: 250_000}(r, a) {
            // If it somehow succeeded, both should be paid (no partial state).
            assertEq(address(0xBEEF).balance, 1 ether);
            assertEq(address(grief).balance, 1 ether);
        } catch {
            // Tx reverted: NEITHER recipient should be paid.
            assertEq(address(0xBEEF).balance, 0, "atomic: BEEF unpaid");
            assertEq(address(grief).balance, 0, "atomic: grief unpaid");
            assertEq(address(sender).balance, 0, "no stuck BNB");
        }
    }

    // =========================================================================
    // 4. Approval race / front-running setFee — M2 slippage cap
    // =========================================================================
    /// @dev User approves max, then owner front-runs setFee from 10 -> 100.
    ///      The user's tx, sent with maxFeeBps=10, MUST revert instead of
    ///      paying 10x the expected fee.
    function testAttack_setFeeFrontRun_blockedByMaxFeeBps() public {
        // Initial state: feeBps = 10.
        vm.prank(owner);
        sender.setFee(10);

        token.mint(user, 1_000_000 ether);
        vm.prank(user);
        token.approve(address(sender), type(uint256).max);

        (address[] memory r, uint256[] memory a) = _singleRecipient(address(0xBEEF), 100_000 ether);

        // ---- mempool: user signs tx with maxFeeBps = 10 ----
        // ---- attacker (owner) front-runs ----
        vm.prank(owner);
        sender.setFee(100);

        // ---- user's tx now executes with feeBps=100 but max=10 ----
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.FeeAboveMax.selector, uint16(100), uint16(10))
        );
        sender.multisendToken(address(token), r, a, 10);
    }

    /// @dev Edge: user passes maxFeeBps = 0 while feeBps == 0. Must succeed.
    function testAttack_maxFeeBpsZero_currentFeeZero_succeeds() public {
        // feeBps already 0 from setUp.
        token.mint(user, 100 ether);
        vm.prank(user);
        token.approve(address(sender), 100 ether);

        (address[] memory r, uint256[] memory a) = _singleRecipient(address(0xBEEF), 100 ether);
        vm.prank(user);
        sender.multisendToken(address(token), r, a, 0);
        assertEq(token.balanceOf(address(0xBEEF)), 100 ether);
    }

    /// @dev Edge: user passes maxFeeBps = 0 while feeBps == 1. Must revert.
    function testAttack_maxFeeBpsZero_currentFeeNonZero_reverts() public {
        vm.prank(owner);
        sender.setFee(1);

        token.mint(user, 100 ether);
        vm.prank(user);
        token.approve(address(sender), 100 ether);

        (address[] memory r, uint256[] memory a) = _singleRecipient(address(0xBEEF), 100 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.FeeAboveMax.selector, uint16(1), uint16(0))
        );
        sender.multisendToken(address(token), r, a, 0);
    }

    // =========================================================================
    // 5. Permit / signature replay — N/A
    // =========================================================================
    /// @dev Documentation test: the contract has no permit / EIP-712 / sig
    ///      pathway. Approvals come from the standard ERC20 `approve` flow,
    ///      whose nonces are managed inside the token itself, not the
    ///      Multisender. There is therefore no signature for an attacker to
    ///      replay against the Multisender. This test simply asserts that no
    ///      such function exists in the deployed ABI by attempting a static
    ///      call to a hypothetical selector; it MUST revert.
    function testAttack_noPermitReplaySurface() public {
        // Hypothetical permit selector that would be vulnerable.
        bytes4 fakePermit = bytes4(keccak256("permitMultisend(address,uint256,uint256,uint8,bytes32,bytes32)"));
        (bool ok, ) = address(sender).call(abi.encodeWithSelector(fakePermit));
        assertFalse(ok, "Multisender must have no permit-style entrypoint");
    }

    // =========================================================================
    // 6. block.timestamp tolerance — 24h delay vs miner skew
    // =========================================================================
    /// @dev BSC validators have negligible timestamp manipulation power
    ///      (PoSA, ~3s blocks, ±15s soft skew). The 24h delay is 5760x larger
    ///      than that skew, so even maximal manipulation cannot bypass it. We
    ///      verify the delay holds at exactly +24h - 1s and unlocks at +24h.
    function testAttack_rescueDelay_tolerantToTimestampSkew() public {
        token.mint(address(sender), 1_000 ether);
        vm.prank(owner);
        sender.queueRescue();

        // 24h - 1s: must still revert.
        vm.warp(block.timestamp + 24 hours - 1);
        vm.prank(owner);
        vm.expectRevert(Multisender.RescueNotReady.selector);
        sender.rescueToken(address(token), 1_000 ether);

        // Even +15s validator skew can't push past 24h - 1.
        // Bump to exactly 24h: must succeed.
        vm.warp(block.timestamp + 1);
        vm.prank(owner);
        sender.rescueToken(address(token), 1_000 ether);
        assertEq(token.balanceOf(owner), 1_000 ether);
    }

    // =========================================================================
    // 7. Storage layout sanity (Ownable2Step + ReentrancyGuard)
    // =========================================================================
    /// @dev Verifies that the inherited storage layout doesn't collide with our
    ///      own state vars. We read each public state slot via its getter; if a
    ///      collision occurred, one of these would alias the others.
    function testAttack_storageLayoutNoCollision() public {
        // After construction:
        //   feeBps = 0, feeReceiver = feeReceiver, rescueQueuedAt = 0
        //   owner() = owner, pendingOwner() = address(0)
        assertEq(sender.feeBps(), 0);
        assertEq(sender.feeReceiver(), feeReceiver);
        assertEq(sender.rescueQueuedAt(), 0);
        assertEq(sender.owner(), owner);
        assertEq(sender.pendingOwner(), address(0));
        // rescueDelay is now constant; reading it MUST yield 24h.
        assertEq(sender.rescueDelay(), 24 hours);

        // Mutate every mutable slot and re-check independence.
        vm.prank(owner);
        sender.setFee(42);
        assertEq(sender.feeBps(), 42, "feeBps slot moved");
        assertEq(sender.feeReceiver(), feeReceiver, "feeReceiver clobbered by feeBps write");
        assertEq(sender.owner(), owner, "owner clobbered");

        vm.prank(owner);
        sender.setFeeReceiver(address(0xBADF00D));
        assertEq(sender.feeReceiver(), address(0xBADF00D));
        assertEq(sender.feeBps(), 42, "feeBps clobbered by feeReceiver write");

        vm.prank(owner);
        sender.queueRescue();
        assertGt(sender.rescueQueuedAt(), 0);
        assertEq(sender.feeBps(), 42, "rescueQueuedAt clobbered feeBps");
        assertEq(sender.feeReceiver(), address(0xBADF00D), "rescueQueuedAt clobbered feeReceiver");

        // Two-step ownership transfer doesn't perturb other slots.
        vm.prank(owner);
        sender.transferOwnership(address(0xB0B));
        assertEq(sender.pendingOwner(), address(0xB0B));
        assertEq(sender.owner(), owner, "owner changed without accept");
        assertEq(sender.feeBps(), 42);
        assertEq(sender.feeReceiver(), address(0xBADF00D));
    }

    // =========================================================================
    // 8. Constructor revert recovery
    // =========================================================================
    /// @dev Deploying with `_feeBps = 101` (above the 1% cap) MUST revert. This
    ///      protects against fat-finger deploy scripts and CI typos.
    function testAttack_constructorRevertsAboveFeeCap() public {
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.FeeTooHigh.selector, uint16(101), uint16(100))
        );
        new Multisender(owner, feeReceiver, 101);
    }

    /// @dev `_feeReceiver = address(0)` MUST revert.
    function testAttack_constructorRevertsZeroReceiver() public {
        vm.expectRevert(Multisender.FeeReceiverZero.selector);
        new Multisender(owner, address(0), 10);
    }

    // =========================================================================
    // 10. Empty token contract address — non-contract `token`
    // =========================================================================
    /// @dev `multisendToken(address(0xdead), …)` where 0xdead has no code MUST
    ///      revert (SafeERC20 in OZ ≥4.9 checks the target via
    ///      `Address.functionCall` which reverts on EOA). No partial state.
    function testAttack_nonContractTokenAddress_reverts() public {
        address nonContract = address(0xDeaD);
        assertEq(nonContract.code.length, 0, "precondition: must be EOA");

        (address[] memory r, uint256[] memory a) = _singleRecipient(address(0xBEEF), 1 ether);

        vm.prank(user);
        // SafeERC20 wraps the non-contract case as `Address.AddressEmptyCode`.
        vm.expectRevert();
        sender.multisendToken(nonContract, r, a, 0);
    }

    // =========================================================================
    // Bonus: rescueQueuedAt reset prevents re-entry-via-rescue
    // =========================================================================
    /// @dev Defence in depth on the rescue path. Two layers must hold:
    ///        1. `rescueQueuedAt` is reset to 0 BEFORE the external call (CEI), so a re-entry
    ///           from the token's hook would hit `RescueNotReady`.
    ///        2. `onlyOwner` blocks the re-entry first, since the inner call is initiated by the
    ///           token contract (msg.sender = token, not owner) -> `OwnableUnauthorizedAccount`.
    ///      Either revert is acceptable; both prove the re-entry can't drain the contract.
    function testAttack_rescueReentryBlocked() public {
        MaliciousReentrantToken evil = new MaliciousReentrantToken();
        evil.mint(address(sender), 1_000 ether);

        // Arm the hook to call rescueToken again.
        bytes memory innerCall = abi.encodeWithSelector(
            sender.rescueToken.selector,
            address(evil),
            uint256(1)
        );
        evil.arm(address(sender), innerCall);

        vm.prank(owner);
        sender.queueRescue();
        vm.warp(block.timestamp + 24 hours + 1);

        // Inner call is initiated by the token contract -> onlyOwner trips first.
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(evil))
        );
        sender.rescueToken(address(evil), 1_000 ether);

        // Sanity: the rescue did not partially execute. Tokens still in contract,
        // queue was rolled back by the revert.
        assertEq(evil.balanceOf(address(sender)), 1_000 ether, "no partial drain");
        assertEq(evil.balanceOf(owner), 0);
    }

    // =========================================================================
    // Bonus: receive() rejects direct BNB even from forced contexts
    // =========================================================================
    /// @dev `receive()` always reverts. Forcing a transfer via `selfdestruct`
    ///      is the only way to deposit BNB, and the audit accepts that as the
    ///      designed escape hatch (rescued via M3).
    function testAttack_receiveRevertsOnDirectBNB() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool ok, ) = address(sender).call{value: 1 ether}("");
        assertFalse(ok, "receive() must reject direct BNB");
        assertEq(address(sender).balance, 0);
    }
}
