// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {JuryToken} from "../src/JuryToken.sol";

/// @notice Stands in for the launch factory: a contract, not an EOA, that deploys the token and
///         therefore becomes `msg.sender` of the constructor.
contract DeployerProbe {
    function deployToken() external returns (JuryToken) {
        return new JuryToken();
    }
}

contract JuryTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    JuryToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new JuryToken();
    }

    // ---------------------------------------------------------------- metadata

    function test_metadata() public view {
        assertEq(token.name(), "JURY");
        assertEq(token.symbol(), "JURY");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "JURY");
        assertEq(token.TOKEN_SYMBOL(), "JURY");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_totalSupplyConstantIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    // ---------------------------------------------------------------- construction

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        new JuryToken();
    }

    function test_contractDeployerReceivesSupply() public {
        // The launch factory is a contract: msg.sender of the constructor is that contract.
        DeployerProbe factory = new DeployerProbe();
        JuryToken deployed = factory.deployToken();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_eachDeploymentIsIndependent() public {
        vm.prank(alice);
        JuryToken second = new JuryToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(second.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1234 ether;
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalanceAndZeroAmount() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.prank(deployer);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5 ether));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(bob, SUPPLY + 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------- approve / transferFrom

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(deployer, alice, 10 ether);
        vm.prank(deployer);
        assertTrue(token.approve(alice, 10 ether));
        assertEq(token.allowance(deployer, alice), 10 ether);

        // Overwrites, does not add.
        vm.prank(deployer);
        token.approve(alice, 3 ether);
        assertEq(token.allowance(deployer, alice), 3 ether);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, bob, 4 ether);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 4 ether));

        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 4 ether);
        assertEq(token.allowance(deployer, alice), 6 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromWithInfiniteAllowanceKeepsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 7 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 7 ether);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 1 ether, 2 ether)
        );
        token.transferFrom(deployer, bob, 2 ether);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromRevertsOnInsufficientBalanceEvenWithAllowance() public {
        vm.prank(alice);
        token.approve(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        token.transferFrom(alice, bob, 1 ether);
    }

    // ---------------------------------------------------------------- no privileged surface

    function test_noMintOrAdminEntrypointExists() public {
        address attacker = makeAddr("attacker");
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "setOwner(address)",
            "transferOwnership(address)",
            "owner()",
            "renounceOwnership()"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool okAttacker,) = address(token).call(data);
            assertFalse(okAttacker, signatures[i]);
            vm.prank(deployer);
            (bool okDeployer,) = address(token).call(data);
            assertFalse(okDeployer, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(attacker), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_deployerCannotMoveAHoldersBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 100 ether);

        vm.prank(alice);
        assertTrue(token.transfer(bob, 50 ether));
        assertEq(token.balanceOf(bob), 50 ether);
    }

    function test_rejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        token.transfer(alice, amount);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY);
        amount = bound(amount, 0, allowance_);
        vm.prank(deployer);
        token.approve(alice, allowance_);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, amount));
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(deployer, alice), allowance_ - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
