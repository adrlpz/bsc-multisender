// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Multisender
/// @notice Non-custodial batch transfer of BNB and BEP-20 tokens on BSC.
/// @dev v1.1.1 — adversarial-pass low-risk hardening on top of v1.1 (no ABI change).
///       v1.1.0 — audit fixes M1/M2/M3, Ownable2Step (L4).
///
///       Adversarial considerations (see docs/AUDIT-V2.md):
///         - Reentrancy on `multisendBNB` / `multisendToken`: blocked by `nonReentrant` and the
///           pull-pattern. Token transfers are atomic; BNB sends use a low-level call but the
///           guard prevents re-entering either entrypoint mid-loop.
///         - Front-running `setFee`: defeated by the `maxFeeBps` slippage cap (M2 fix).
///         - Owner griefing via `setFee` / rescue: capped at `MAX_FEE_BPS` (1%) and gated by the
///           24h `rescueDelay` (M3 fix). Owner is expected to be a multisig.
///         - Fee-on-transfer / rebasing tokens: rejected by the post-transfer balance-delta check
///           (M1 fix).
///         - Out-of-gas griefing by a malicious recipient: the whole tx reverts atomically;
///           recipients earlier in the batch are not paid until the tx succeeds.
///       Two tiers:
///       - Free tier: `multisendBNB` (≤ MAX_RECIPIENTS_FREE, no protocol fee).
///       - Standard tier: `multisendToken` (≤ MAX_RECIPIENTS_STANDARD, fee = totalAmount * feeBps / 10_000).
///       Tokens are pulled from the sender via SafeERC20 (sender must `approve` the contract first).
///
///       v1.1 changes:
///         - L4: Ownable2Step — ownership transfer is now two-step (transferOwnership + acceptOwnership).
///         - M2: `multisendToken` accepts `maxFeeBps` slippage guard. Reverts if current `feeBps`
///               exceeds caller-supplied max. Frontend should pass the value of `feeBps()` read at
///               quote time for zero-slippage protection against a front-running `setFee` call.
///         - M3: `rescueToken` / `rescueBNB` require `queueRescue()` + a 24h `rescueDelay` to elapse.
///               After execution, the queue is reset to enforce per-rescue commitment.
///         - M1: Fee-on-transfer / rebasing tokens are explicitly unsupported. `multisendToken`
///               verifies `balanceOf(recipient)` increases by exactly `amt` post-transfer; mismatched
///               deltas revert with `FeeOnTransferNotSupported`. This adds gas (one SLOAD per
///               recipient) but guarantees recipients receive exactly the promised amount.
///
///       Simplification vs PRD §11: the PRD describes a "0.1% capped at 0.5 BNB" fee for the Standard
///       tier across all assets. Implementing a BNB-denominated cap on arbitrary BEP-20 tokens
///       requires an oracle (Chainlink/PancakePair) which is out of MVP scope. We therefore:
///         - keep `multisendBNB` free-only (≤ 50 recipients, fee = 0);
///         - charge the protocol fee in the same token on `multisendToken` (no cap).
///       `FEE_CAP` is exported as a public constant for future BNB-variant use; it is NOT applied
///       in this version. See CONTRACTS.md for the rationale.
contract Multisender is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    /// @notice Maximum recipients in a single Free-tier (BNB) call.
    uint256 public constant MAX_RECIPIENTS_FREE = 50;

    /// @notice Maximum recipients in a single Standard-tier (token) call.
    uint256 public constant MAX_RECIPIENTS_STANDARD = 1000;

    /// @notice Hard upper bound for `feeBps` (1.00%).
    uint16 public constant MAX_FEE_BPS = 100;

    /// @notice BNB-denominated fee cap reserved for a future BNB Standard variant. Not applied here.
    uint256 public constant FEE_CAP = 0.5 ether;

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------

    /// @notice Protocol fee in basis points (1 bps = 0.01%). Capped at `MAX_FEE_BPS`.
    uint16 public feeBps;

    /// @notice Address that receives protocol fees.
    address public feeReceiver;

    /// @notice Mandatory delay between `queueRescue()` and a rescue execution (M3).
    /// @dev v1.1.1: declared `constant` (was a mutable storage var in v1.1). The value is fixed
    ///      at 24h and never changed on-chain, so promoting it to `constant` removes a SLOAD per
    ///      rescue check and aligns the source with reality (Slither `constable-states`).
    ///      The auto-generated `rescueDelay()` getter still exists and returns the same value, so
    ///      no off-chain caller breaks.
    uint256 public constant rescueDelay = 24 hours;

    /// @notice Timestamp at which the most recent rescue was queued. `0` means no queue.
    uint256 public rescueQueuedAt;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event MultisendBNB(address indexed sender, uint256 totalAmount, uint256 recipientCount);
    event MultisendToken(
        address indexed sender,
        address indexed token,
        uint256 totalAmount,
        uint256 recipientCount,
        uint256 fee
    );
    event FeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    /// @notice Emitted when an admin queues a rescue. `readyAt` is the earliest timestamp at which
    ///         `rescueToken` / `rescueBNB` will succeed.
    event RescueQueued(uint256 readyAt);
    /// @notice Emitted when a rescue executes. `token == address(0)` for BNB rescues.
    /// @dev v1.1.1: `token` is now `indexed` so off-chain indexers can filter rescue events per
    ///      asset. Event name and arg order are unchanged; the topic count goes from 1 to 2.
    event RescueExecuted(address indexed token, uint256 amount);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error LengthMismatch();
    error NoRecipients();
    error TooManyRecipients(uint256 provided, uint256 max);
    error ZeroAmount(uint256 index);
    error ZeroAddress(uint256 index);
    error ValueMismatch(uint256 sent, uint256 expected);
    error FeeTooHigh(uint16 provided, uint16 max);
    error FeeReceiverZero();
    error BNBTransferFailed(address recipient);
    error InsufficientBNB();

    /// @notice M2: current `feeBps` exceeds the caller-provided slippage cap.
    error FeeAboveMax(uint16 actual, uint16 max);
    /// @notice M3: rescue called without a queue, or before `rescueQueuedAt + rescueDelay`.
    error RescueNotReady();
    /// @notice M3: a rescue is already queued.
    error RescueAlreadyQueued();
    /// @notice M1: token took a transfer fee or rebased — recipient delta does not match the requested amount.
    error FeeOnTransferNotSupported();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    /// @param _owner            Initial contract owner. Ownership transfer is two-step (Ownable2Step).
    /// @param _feeReceiver      Address that receives protocol fees.
    /// @param _feeBps           Initial fee in basis points (≤ MAX_FEE_BPS).
    constructor(address _owner, address _feeReceiver, uint16 _feeBps) Ownable(_owner) {
        if (_feeReceiver == address(0)) revert FeeReceiverZero();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps, MAX_FEE_BPS);
        feeReceiver = _feeReceiver;
        feeBps = _feeBps;
    }

    // ---------------------------------------------------------------------
    // Free tier — BNB
    // ---------------------------------------------------------------------

    /// @notice Send BNB to many recipients in one tx. Free tier — no protocol fee.
    /// @param recipients Recipient addresses.
    /// @param amounts    Amount per recipient (wei). Must equal `msg.value` in aggregate.
    function multisendBNB(address[] calldata recipients, uint256[] calldata amounts)
        external
        payable
        nonReentrant
    {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        if (len == 0) revert NoRecipients();
        if (len > MAX_RECIPIENTS_FREE) revert TooManyRecipients(len, MAX_RECIPIENTS_FREE);

        uint256 total;
        for (uint256 i = 0; i < len;) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (to == address(0)) revert ZeroAddress(i);
            if (amt == 0) revert ZeroAmount(i);
            unchecked {
                total += amt;
                ++i;
            }
        }

        if (msg.value != total) revert ValueMismatch(msg.value, total);

        for (uint256 i = 0; i < len;) {
            (bool ok,) = recipients[i].call{value: amounts[i]}("");
            if (!ok) revert BNBTransferFailed(recipients[i]);
            unchecked {
                ++i;
            }
        }

        emit MultisendBNB(msg.sender, total, len);
    }

    // ---------------------------------------------------------------------
    // Standard tier — BEP-20
    // ---------------------------------------------------------------------

    /// @notice Send a BEP-20 token to many recipients in one tx. Standard tier.
    /// @dev Fee is charged in the same token: `fee = totalAmount * feeBps / 10_000` (no BNB cap).
    ///      Sender must approve this contract for `totalAmount + fee` (or use infinite approval).
    ///
    ///      M1: Fee-on-transfer / rebasing tokens are NOT supported. After each `safeTransferFrom`
    ///      we verify `balanceOf(to)` increased by exactly `amt`; any deviation reverts with
    ///      `FeeOnTransferNotSupported`. This costs one extra SLOAD per recipient but guarantees
    ///      recipients receive the exact amount.
    ///
    ///      M2: `maxFeeBps` is a caller-supplied slippage guard. Pass the value of `feeBps()` read
    ///      at quote time for zero slippage. If a `setFee` lands before this tx, the call reverts
    ///      instead of silently overcharging.
    /// @param token      BEP-20 token address.
    /// @param recipients Recipient addresses.
    /// @param amounts    Amount per recipient.
    /// @param maxFeeBps  Maximum acceptable `feeBps` (slippage cap).
    function multisendToken(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint16 maxFeeBps
    ) external nonReentrant {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        if (len == 0) revert NoRecipients();
        if (len > MAX_RECIPIENTS_STANDARD) revert TooManyRecipients(len, MAX_RECIPIENTS_STANDARD);

        // M2: slippage guard — refuse if owner front-ran a setFee.
        uint16 currentFeeBps = feeBps;
        if (currentFeeBps > maxFeeBps) revert FeeAboveMax(currentFeeBps, maxFeeBps);

        IERC20 erc20 = IERC20(token);

        uint256 total;
        for (uint256 i = 0; i < len;) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (to == address(0)) revert ZeroAddress(i);
            if (amt == 0) revert ZeroAmount(i);

            // M1: balance-delta check — fee-on-transfer / rebasing tokens revert.
            uint256 beforeBal = erc20.balanceOf(to);
            erc20.safeTransferFrom(msg.sender, to, amt);
            if (erc20.balanceOf(to) - beforeBal != amt) revert FeeOnTransferNotSupported();

            unchecked {
                total += amt;
                ++i;
            }
        }

        uint256 fee;
        if (currentFeeBps != 0) {
            fee = (total * currentFeeBps) / 10_000;
            if (fee != 0) {
                erc20.safeTransferFrom(msg.sender, feeReceiver, fee);
            }
        }

        emit MultisendToken(msg.sender, token, total, len, fee);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /// @notice Update protocol fee. Capped at `MAX_FEE_BPS` (1%).
    function setFee(uint16 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh(_feeBps, MAX_FEE_BPS);
        uint16 old = feeBps;
        feeBps = _feeBps;
        emit FeeUpdated(old, _feeBps);
    }

    /// @notice Update fee receiver. Must be non-zero.
    function setFeeReceiver(address _receiver) external onlyOwner {
        if (_receiver == address(0)) revert FeeReceiverZero();
        address old = feeReceiver;
        feeReceiver = _receiver;
        emit FeeReceiverUpdated(old, _receiver);
    }

    /// @notice M3: Queue a rescue. Must be called before `rescueToken` / `rescueBNB`. After the
    ///         24h `rescueDelay` elapses, exactly one rescue may execute; the queue is then reset.
    function queueRescue() external onlyOwner {
        if (rescueQueuedAt != 0) revert RescueAlreadyQueued();
        rescueQueuedAt = block.timestamp;
        emit RescueQueued(block.timestamp + rescueDelay);
    }

    /// @notice Emergency: rescue tokens stuck in this contract.
    /// @dev The contract is transit-only by design; this exists for accidental direct transfers.
    ///      M3: requires a prior `queueRescue()` and `rescueDelay` to have elapsed.
    ///
    ///      v1.1.1 (CEI): `RescueExecuted` is emitted BEFORE the external token call. Re-entry is
    ///      additionally blocked by resetting `rescueQueuedAt` to 0 before the call — a malicious
    ///      token hook that re-enters `rescueToken` / `rescueBNB` hits `RescueNotReady`.
    function rescueToken(address token, uint256 amount) external onlyOwner {
        if (rescueQueuedAt == 0 || block.timestamp < rescueQueuedAt + rescueDelay) {
            revert RescueNotReady();
        }
        rescueQueuedAt = 0;
        emit RescueExecuted(token, amount);
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Emergency: rescue BNB stuck in this contract.
    /// @dev M3: requires a prior `queueRescue()` and `rescueDelay` to have elapsed.
    ///      v1.1.1 (CEI): event emitted BEFORE the external `call`. Re-entry is blocked by the
    ///      `rescueQueuedAt = 0` write that precedes both the event and the call.
    function rescueBNB(uint256 amount) external onlyOwner {
        if (rescueQueuedAt == 0 || block.timestamp < rescueQueuedAt + rescueDelay) {
            revert RescueNotReady();
        }
        if (amount > address(this).balance) revert InsufficientBNB();
        rescueQueuedAt = 0;
        emit RescueExecuted(address(0), amount);
        (bool ok,) = owner().call{value: amount}("");
        if (!ok) revert BNBTransferFailed(owner());
    }

    /// @notice Reject stray BNB (only accepted via `multisendBNB`).
    receive() external payable {
        revert("Multisender: direct BNB not accepted");
    }
}
