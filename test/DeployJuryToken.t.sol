// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployJuryToken} from "../script/DeployJuryToken.s.sol";
import {JuryToken} from "../src/JuryToken.sol";

contract DeployJuryTokenTest is Test {
    function test_deployMintsSupplyToTheScriptCaller() public {
        DeployJuryToken deployer = new DeployJuryToken();
        JuryToken token = deployer.deploy();
        // `deploy()` runs as the script contract, so the script contract is the constructor's
        // msg.sender and holds the supply: exactly the factory's position at launch.
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(deployer)), 1_000_000_000 ether);
        assertEq(token.name(), "JURY");
        assertEq(token.symbol(), "JURY");
        assertEq(token.decimals(), 18);
    }
}
