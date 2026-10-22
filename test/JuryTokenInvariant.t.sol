// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {JuryToken} from "src/JuryToken.sol";

/// @notice Drives a closed set of four holders, including the original deployer.
/// @dev Expected balances come from the specified initial supply and authorized net flows,
/// never from balanceOf. Expected allowances likewise come only from requested approvals
/// and successful spending. A revert leaves the ledger unchanged.
contract JuryTokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    JuryToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public sent;
    mapping(address => uint256) public received;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(JuryToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function expectedBalance(address actor) public view returns (uint256) {
        uint256 initial = actor == actors[0] ? SUPPLY : 0;
        return initial + received[actor] - sent[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, expectedBalance(from));
        _transfer(from, to, amount);
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance(from));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        // Deliberately revisit revocation and infinite approval as well as ordinary and
        // unrestricted uint256 approvals. Approvals are allowed to exceed the supply.
        if (mode % 4 == 0) amount = 0;
        else if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(amount, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance(owner);
        if (allowed < limit) limit = allowed;
        amount = bound(amount, 0, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "authorized delegated transfer failed");
        sent[owner] += amount;
        received[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(from);
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        uint256 allowed
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 1, SUPPLY);
        allowed = bound(allowed, 0, amount - 1);
        _approve(owner, spender, allowed);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        assertEq(token.allowance(owner, spender), allowed, "failed call spent allowance");
    }

    function rejectTransferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, balance + 1, type(uint256).max);
        uint256 allowed = infinite ? type(uint256).max : amount;
        _approve(owner, spender, allowed);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        assertEq(token.allowance(owner, spender), allowed, "failed transfer did not roll back allowance");
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        amount = bound(amount, 0, expectedBalance(owner));
        if (mode % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (mode % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amount);
        } else {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
            assertEq(token.allowance(owner, spender), amount, "invalid recipient consumed approval");
        }
    }

    function rejectSupplyMutation(uint256 callerSeed, uint256 ownerSeed, uint256 amount, uint8 mode) external {
        address caller = _actor(callerSeed);
        address owner = _actor(ownerSeed);
        bytes memory data;
        if (mode % 6 == 0) data = abi.encodeWithSignature("mint(address,uint256)", owner, amount);
        else if (mode % 6 == 1) data = abi.encodeWithSignature("mint(uint256)", amount);
        else if (mode % 6 == 2) data = abi.encodeWithSignature("mint()");
        else if (mode % 6 == 3) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (mode % 6 == 4) data = abi.encodeWithSignature("burnFrom(address,uint256)", owner, amount);
        else data = abi.encodeWithSignature("initialize(address)", owner);

        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        assertFalse(ok, "unexpected supply-changing entry point");
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approval failed");
        expectedAllowance[owner][spender] = amount;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "funded holder cannot transfer");
        sent[from] += amount;
        received[to] += amount;
    }
}

/// @notice Conservation, individual accounting, permissions and eventual spendability after
/// random sequences of successful transfers, approvals, revocations and rejected operations.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract JuryTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    JuryToken internal token;
    JuryTokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant holder ", vm.toString(i)));
        }
        vm.prank(actors[0]);
        token = new JuryToken();
        handler = new JuryTokenHandler(token, actors);

        // All holders begin funded, with a ring of spendable allowances. This reaches
        // meaningful delegated transfers from the start, while other pairs are unauthorized.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY / 8, 3);
        }
        handler.approve(0, 1, type(uint256).max, 1);

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.rejectTransferAboveBalance.selector;
        selectors[5] = handler.rejectTransferFromAboveAllowance.selector;
        selectors[6] = handler.rejectTransferFromAboveBalance.selector;
        selectors[7] = handler.rejectZeroAddress.selector;
        selectors[8] = handler.rejectSupplyMutation.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndEveryTokenIsAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after construction");
        assertEq(sum, SUPPLY, "tokens were lost or created during a sequence");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesMatchAuthorizedNetTransfers() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "holder accounting mismatch");
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "permission changed without approval or successful spending"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    function afterInvariant() public {
        // Regardless of sequence order, every remaining holder can transfer their full
        // balance back to the deployer. This also checks the last wei of every balance.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transferAll(i, 0);
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_supplyIsFixedAndEveryTokenIsAccountedFor();
        invariant_balancesMatchAuthorizedNetTransfers();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
    }

    function test_handlerExercisesSuccessAndRejectionBranches() public {
        // A deterministic harness check ensures the random campaign is not the only way
        // to reach nonzero delegated spending, aliasing, or each rejection dispatcher arm.
        handler.transfer(0, 1, 1);
        handler.transferFrom(0, 1, 2, 1);
        handler.approve(2, 3, 2, 3);
        handler.transferFrom(2, 3, 2, 2);
        handler.approve(2, 3, 0, 0);
        handler.rejectTransferAboveBalance(1, 1, type(uint256).max);
        handler.rejectTransferFromAboveAllowance(0, 1, 2, 1, 0);
        handler.rejectTransferFromAboveBalance(0, 1, 2, type(uint256).max - 1, false);
        handler.rejectTransferFromAboveBalance(0, 1, 2, type(uint256).max, true);
        for (uint8 mode; mode < 3; ++mode) {
            handler.rejectZeroAddress(0, 1, 1, mode);
        }
        for (uint8 mode; mode < 6; ++mode) {
            handler.rejectSupplyMutation(0, 1, 1, mode);
        }
        invariant_supplyIsFixedAndEveryTokenIsAccountedFor();
        invariant_balancesMatchAuthorizedNetTransfers();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
        afterInvariant();
    }
}
