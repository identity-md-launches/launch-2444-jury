// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {JuryToken} from "src/JuryToken.sol";

/// @notice Boundary and algebraic properties complementing the existing deployment/ERC-20 tests.
/// forge-config: default.fuzz.runs = 1000
contract JuryTokenPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    JuryToken internal token;
    address internal holder = makeAddr("properties holder");
    address internal spender = makeAddr("properties spender");
    address internal recipient = makeAddr("properties recipient");
    address internal stranger = makeAddr("properties stranger");

    function setUp() public {
        vm.prank(holder);
        token = new JuryToken();
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(holder);
        JuryToken fresh = new JuryToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1, "constructor must mint once");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(holder))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(holder), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_oneWeiAndLastWeiAreTransferable() public {
        _transfer(holder, recipient, SUPPLY - 1);
        assertEq(token.balanceOf(holder), 1);
        _transfer(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transfer(recipient, 1);
        assertEq(token.balanceOf(recipient), SUPPLY);
    }

    function test_zeroTransfersEmitEvenWithoutBalanceOrAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(stranger, recipient, 0);
        _transfer(stranger, recipient, 0);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(stranger, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(stranger, recipient, 0));
        assertEq(token.allowance(stranger, spender), 0);
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_zeroValueDoesNotBypassInvalidReceiverOrSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(holder);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroSenderCannotTransferOrApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(recipient, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 1);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_transferFromZeroOwnerCannotCreateTokens() public {
        // No authorization can originate from zero; even a zero-value delegated call must fail.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), recipient, 0);
        assertEq(token.balanceOf(address(0)), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_selfTransferRequiresSufficientBalance() public {
        _transfer(holder, holder, SUPPLY);
        assertEq(token.balanceOf(holder), SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        vm.prank(holder);
        token.transfer(holder, SUPPLY + 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_transferFromToOwnerSpendsAllowanceButPreservesBalance() public {
        _approve(holder, spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, holder, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, SUPPLY));
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(SUPPLY, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, holder, 1);
    }

    function test_ownerCallingTransferFromStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);

        _approve(holder, holder, 1);
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_maximumTransferIsRejectedWithoutOverflowOrStateChanges() public {
        uint256 maximum = type(uint256).max;
        _approve(holder, spender, maximum);
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, maximum);
        vm.expectRevert(expected);
        vm.prank(holder);
        token.transfer(recipient, maximum);
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(holder, recipient, maximum);
        assertEq(token.allowance(holder, spender), maximum);
        _assertBalances(SUPPLY, 0);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        _approve(holder, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_replacingInfiniteAllowanceAndRevokingAreEffectiveImmediately() public {
        _approve(holder, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max);

        _approve(holder, spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 1);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(holder, spender, 0);
        _approve(holder, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(SUPPLY - 2, 2);
    }

    function test_approvalsAreIsolatedByBothOwnerAndSpender() public {
        _transfer(holder, recipient, 10);
        _approve(holder, spender, 5);
        _approve(recipient, spender, 7);
        _approve(holder, stranger, 9);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 3));
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.allowance(recipient, spender), 7);
        assertEq(token.allowance(holder, stranger), 9);
        assertEq(token.allowance(recipient, stranger), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transferFrom(recipient, holder, 1);
        _assertBalances(SUPPLY - 13, 13);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndDoesNotSpendApproval(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(holder, spender, type(uint256).max);
        _transfer(holder, recipient, amount);
        _assertBalances(SUPPLY - amount, amount);
        _transfer(recipient, holder, amount);
        _assertBalances(SUPPLY, 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
    }

    function testFuzz_splitTransfersEqualOneTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        vm.prank(holder);
        JuryToken combined = new JuryToken();

        _transfer(holder, recipient, first);
        _transfer(holder, recipient, second);
        vm.prank(holder);
        assertTrue(combined.transfer(recipient, first + second));

        assertEq(token.balanceOf(holder), combined.balanceOf(holder));
        assertEq(token.balanceOf(recipient), combined.balanceOf(recipient));
        _assertBalances(SUPPLY - first - second, first + second);
        assertEq(combined.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalOverwritesAndIsIdempotent(uint256 first, uint256 replacement) public {
        _approve(holder, spender, first);
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_finiteAllowanceCanBeSpentExactlyOnce(uint256 amount, uint256 first) public {
        amount = bound(amount, 1, SUPPLY);
        first = bound(first, 0, amount);
        _approve(holder, spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        assertEq(token.allowance(holder, spender), amount - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount - first));
        assertEq(token.allowance(holder, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        _assertBalances(SUPPLY - amount, amount);
    }

    function testFuzz_insufficientAllowancePreservesAllState(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 1, SUPPLY);
        allowed = bound(allowed, 0, amount - 1);
        _approve(holder, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), allowed);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_insufficientBalanceRollsBackAllowance(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        _transfer(holder, recipient, SUPPLY - balance);
        uint256 allowed = infinite ? type(uint256).max : amount;
        _approve(holder, spender, allowed);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), allowed, "failed spend consumed approval");
        _assertBalances(balance, SUPPLY - balance);
    }

    function testFuzz_invalidReceiverRollsBackAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 allowed = infinite ? type(uint256).max : amount;
        _approve(holder, spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), allowed);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_infiniteAllowanceSurvivesRepeatedSpending(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        _approve(holder, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, second));
        assertEq(token.allowance(holder, spender), type(uint256).max);
        _assertBalances(SUPPLY - first - second, first + second);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function _approve(address owner, address spender_, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender_, amount));
    }

    function _assertBalances(uint256 holderBalance, uint256 recipientBalance) internal view {
        assertEq(token.balanceOf(holder), holderBalance);
        assertEq(token.balanceOf(recipient), recipientBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
