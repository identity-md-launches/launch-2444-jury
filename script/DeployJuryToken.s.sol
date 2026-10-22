// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {JuryToken} from "../src/JuryToken.sol";

/// @notice Local / dry-run deployment of `JuryToken`. The production launch does not use this
///         script: IMD's ProjectFactory deploys the token from its built bytecode and receives the
///         supply as `msg.sender` of the constructor. This script exists so the deployment can be
///         rehearsed on a local node and so its parameters are reviewable in code.
/// @dev    The token takes no constructor arguments; there is nothing to configure. `run()` reads
///         nothing from the environment: the broadcasting account comes from forge's own flags.
contract DeployJuryToken is Script {
    /// @notice Deploys one `JuryToken`; whoever calls this becomes the supply holder.
    function deploy() public returns (JuryToken token) {
        token = new JuryToken();
    }

    function run() external returns (JuryToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
