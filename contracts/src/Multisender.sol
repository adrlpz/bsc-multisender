// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Multisender
/// @notice Non-custodial batch transfer of BNB and BEP-20 tokens on BSC.
/// @dev Two tiers:
///       - Free tier: `multisendBNB` (≤ MAX_RECIPIENTS_FREE, no protocol fee).
///       - Standard tier: `multisendToken` (≤ MAX_RECIPIENTS_STANDARD, fee = totalAmount * feeBps / 10_000).
///       Tokens are pulled from the sender via SafeERC20 (sender must `approve` the contract first).
///
///       Simplification vs PRD §11: the PRD describes a "0.1% capped at 0.5 BNB" fee for the Standard
///       tier across all assets. Implementing a BNB-denominated cap on arbitrary BEP-20 tokens
///       requires an oracle (Chainlink/PancakePair) which is out of MVP scope. We therefore:
///         - keep `multisendBNB` free-only (≤ 50 recipients, fee = 0);
///         - charge the protocol fee in the same token on `multisendToken` (no cap).
///       `FEE_CAP` is exported as a public constant for future BNB-variant use; it is NOT applied
///       in this version. See CONTRACTS.md for the rationale.
contract Multisender is Ownable, ReentrancyGuard {
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

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    /// @param _owner            Initial contract owner.
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
    /// @param token      BEP-20 token address.
    /// @param recipients Recipient addresses.
    /// @param amounts    Amount per recipient.
    function multisendToken(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        if (len == 0) revert NoRecipients();
        if (len > MAX_RECIPIENTS_STANDARD) revert TooManyRecipients(len, MAX_RECIPIENTS_STANDARD);

        IERC20 erc20 = IERC20(token);

        uint256 total;
        for (uint256 i = 0; i < len;) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (to == address(0)) revert ZeroAddress(i);
            if (amt == 0) revert ZeroAmount(i);

            erc20.safeTransferFrom(msg.sender, to, amt);

            unchecked {
                total += amt;
                ++i;
            }
        }

        uint256 fee;
        if (feeBps != 0) {
            fee = (total * feeBps) / 10_000;
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

    /// @notice Emergency: rescue tokens stuck in this contract.
    /// @dev The contract is transit-only by design; this exists for accidental direct transfers.
    function rescueToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Emergency: rescue BNB stuck in this contract.
    function rescueBNB(uint256 amount) external onlyOwner {
        if (amount > address(this).balance) revert InsufficientBNB();
        (bool ok,) = owner().call{value: amount}("");
        if (!ok) revert BNBTransferFailed(owner());
    }

    /// @notice Reject stray BNB (only accepted via `multisendBNB`).
    receive() external payable {
        revert("Multisender: direct BNB not accepted");
    }
}
