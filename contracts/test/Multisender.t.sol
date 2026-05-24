// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Multisender} from "../src/Multisender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Minimal mintable ERC20 used in tests.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MultisenderTest is Test {
    Multisender internal sender;
    MockERC20 internal token;

    address internal owner = address(0xA11CE);
    address internal feeReceiver = address(0xFEE);
    address internal user = address(0xCAFE);

    function setUp() public {
        sender = new Multisender(owner, feeReceiver, 0);
        token = new MockERC20();
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    function _makeRecipients(uint256 n) internal pure returns (address[] memory r) {
        r = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            // start at 1000 to avoid precompile addresses (1..9)
            r[i] = address(uint160(1000 + i));
        }
    }

    function _equalAmounts(uint256 n, uint256 each) internal pure returns (uint256[] memory a) {
        a = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            a[i] = each;
        }
    }

    // ---------------------------------------------------------------
    // multisendBNB
    // ---------------------------------------------------------------

    function testMultisendBNB_happy() public {
        address[] memory r = _makeRecipients(3);
        uint256[] memory a = new uint256[](3);
        a[0] = 1 ether;
        a[1] = 2 ether;
        a[2] = 3 ether;
        uint256 total = 6 ether;

        vm.deal(user, total);
        vm.prank(user);
        sender.multisendBNB{value: total}(r, a);

        assertEq(r[0].balance, 1 ether);
        assertEq(r[1].balance, 2 ether);
        assertEq(r[2].balance, 3 ether);
        assertEq(address(sender).balance, 0);
    }

    function testMultisendBNB_revertOnLengthMismatch() public {
        address[] memory r = _makeRecipients(2);
        uint256[] memory a = new uint256[](3);
        a[0] = 1;
        a[1] = 1;
        a[2] = 1;

        vm.deal(user, 3);
        vm.prank(user);
        vm.expectRevert(Multisender.LengthMismatch.selector);
        sender.multisendBNB{value: 3}(r, a);
    }

    function testMultisendBNB_revertOnExceedFreeLimit() public {
        uint256 n = 51;
        address[] memory r = _makeRecipients(n);
        uint256[] memory a = _equalAmounts(n, 1);

        vm.deal(user, n);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.TooManyRecipients.selector, n, sender.MAX_RECIPIENTS_FREE())
        );
        sender.multisendBNB{value: n}(r, a);
    }

    function testMultisendBNB_revertOnInsufficientValue() public {
        address[] memory r = _makeRecipients(2);
        uint256[] memory a = new uint256[](2);
        a[0] = 1 ether;
        a[1] = 1 ether;

        vm.deal(user, 2 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Multisender.ValueMismatch.selector, 1 ether, 2 ether));
        sender.multisendBNB{value: 1 ether}(r, a);
    }

    function testMultisendBNB_revertOnZeroAmount() public {
        address[] memory r = _makeRecipients(2);
        uint256[] memory a = new uint256[](2);
        a[0] = 1 ether;
        a[1] = 0;

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Multisender.ZeroAmount.selector, 1));
        sender.multisendBNB{value: 1 ether}(r, a);
    }

    // ---------------------------------------------------------------
    // multisendToken
    // ---------------------------------------------------------------

    function testMultisendToken_happy() public {
        // Set fee to 0.1% (10 bps) and fund user.
        vm.prank(owner);
        sender.setFee(10);

        address[] memory r = _makeRecipients(3);
        uint256[] memory a = new uint256[](3);
        a[0] = 1_000 ether;
        a[1] = 2_000 ether;
        a[2] = 3_000 ether;
        uint256 total = 6_000 ether;
        uint256 expectedFee = (total * 10) / 10_000; // 6 tokens

        token.mint(user, total + expectedFee);
        vm.prank(user);
        token.approve(address(sender), total + expectedFee);

        vm.prank(user);
        sender.multisendToken(address(token), r, a);

        assertEq(token.balanceOf(r[0]), 1_000 ether);
        assertEq(token.balanceOf(r[1]), 2_000 ether);
        assertEq(token.balanceOf(r[2]), 3_000 ether);
        assertEq(token.balanceOf(feeReceiver), expectedFee);
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(sender)), 0);
    }

    function testMultisendToken_revertOnExceedStandardLimit() public {
        uint256 n = 1001;
        address[] memory r = _makeRecipients(n);
        uint256[] memory a = _equalAmounts(n, 1);

        // No funding needed — should revert on the length check first.
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Multisender.TooManyRecipients.selector, n, sender.MAX_RECIPIENTS_STANDARD())
        );
        sender.multisendToken(address(token), r, a);
    }

    function testMultisendToken_feeCalculation() public {
        // Fee = 0.1% (10 bps). total = 12_345 ether → fee = 12.345 ether.
        vm.prank(owner);
        sender.setFee(10);

        address[] memory r = _makeRecipients(2);
        uint256[] memory a = new uint256[](2);
        a[0] = 5_000 ether;
        a[1] = 7_345 ether;
        uint256 total = 12_345 ether;
        uint256 expectedFee = (total * 10) / 10_000;
        assertEq(expectedFee, 12.345 ether);

        token.mint(user, total + expectedFee);
        vm.prank(user);
        token.approve(address(sender), total + expectedFee);

        vm.prank(user);
        sender.multisendToken(address(token), r, a);

        assertEq(token.balanceOf(feeReceiver), expectedFee);
    }

    function testMultisendToken_zeroFeeSkipsFeeTransfer() public {
        // feeBps == 0 by default in setUp. Ensure no transfer to feeReceiver happens.
        address[] memory r = _makeRecipients(1);
        uint256[] memory a = new uint256[](1);
        a[0] = 100 ether;

        token.mint(user, 100 ether);
        vm.prank(user);
        token.approve(address(sender), 100 ether);

        vm.prank(user);
        sender.multisendToken(address(token), r, a);

        assertEq(token.balanceOf(feeReceiver), 0);
        assertEq(token.balanceOf(r[0]), 100 ether);
    }

    function testMultisendToken_revertOnLengthMismatch() public {
        address[] memory r = _makeRecipients(2);
        uint256[] memory a = new uint256[](3);

        vm.prank(user);
        vm.expectRevert(Multisender.LengthMismatch.selector);
        sender.multisendToken(address(token), r, a);
    }

    function testMultisendToken_revertOnZeroAmount() public {
        address[] memory r = _makeRecipients(2);
        uint256[] memory a = new uint256[](2);
        a[0] = 1 ether;
        a[1] = 0;

        token.mint(user, 1 ether);
        vm.prank(user);
        token.approve(address(sender), 1 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Multisender.ZeroAmount.selector, 1));
        sender.multisendToken(address(token), r, a);
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------

    function testSetFee_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        sender.setFee(50);

        vm.prank(owner);
        sender.setFee(50);
        assertEq(sender.feeBps(), 50);
    }

    function testSetFee_revertAboveCap() public {
        uint16 maxBps = sender.MAX_FEE_BPS();
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Multisender.FeeTooHigh.selector, uint16(101), maxBps));
        sender.setFee(101);
    }

    function testSetFeeReceiver_onlyOwner() public {
        address newRcv = address(0xBEEF);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        sender.setFeeReceiver(newRcv);

        vm.prank(owner);
        sender.setFeeReceiver(newRcv);
        assertEq(sender.feeReceiver(), newRcv);
    }

    function testSetFeeReceiver_revertOnZero() public {
        vm.prank(owner);
        vm.expectRevert(Multisender.FeeReceiverZero.selector);
        sender.setFeeReceiver(address(0));
    }

    function testRescueToken() public {
        // Simulate stuck tokens.
        token.mint(address(sender), 1_000 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        sender.rescueToken(address(token), 1_000 ether);

        vm.prank(owner);
        sender.rescueToken(address(token), 1_000 ether);
        assertEq(token.balanceOf(owner), 1_000 ether);
        assertEq(token.balanceOf(address(sender)), 0);
    }

    function testRescueBNB() public {
        // Force-send BNB via selfdestruct since `receive()` reverts.
        SelfDestructor sd = new SelfDestructor{value: 5 ether}();
        sd.boom(payable(address(sender)));
        assertEq(address(sender).balance, 5 ether);

        vm.prank(owner);
        sender.rescueBNB(5 ether);
        assertEq(owner.balance, 5 ether);
        assertEq(address(sender).balance, 0);
    }

    function testReceive_revertsOnDirectBNB() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool ok,) = address(sender).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // ---------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------

    function testFuzz_multisendBNB(uint8 n, uint64 amount) public {
        // Bound to the Free tier and skip degenerate inputs.
        uint256 count = bound(uint256(n), 1, sender.MAX_RECIPIENTS_FREE());
        uint256 each = bound(uint256(amount), 1, 1 ether);

        address[] memory r = _makeRecipients(count);
        uint256[] memory a = _equalAmounts(count, each);
        uint256 total = each * count;

        vm.deal(user, total);
        vm.prank(user);
        sender.multisendBNB{value: total}(r, a);

        for (uint256 i = 0; i < count; i++) {
            assertEq(r[i].balance, each);
        }
        assertEq(address(sender).balance, 0);
    }
}

/// @dev Helper to force-send BNB to a contract that rejects normal transfers.
contract SelfDestructor {
    constructor() payable {}

    function boom(address payable to) external {
        selfdestruct(to);
    }
}
