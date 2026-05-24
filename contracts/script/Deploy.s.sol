// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Multisender} from "../src/Multisender.sol";

/// @notice Deploys Multisender to the active network.
/// @dev    Defaults: feeReceiver = msg.sender, feeBps = 0 (launch promo).
///         Override via env: FEE_RECEIVER, FEE_BPS.
///         Run: forge script script/Deploy.s.sol --rpc-url $BSC_RPC --broadcast --verify
contract Deploy is Script {
    function run() external returns (Multisender deployed) {
        address feeReceiver = vm.envOr("FEE_RECEIVER", msg.sender);
        uint16 feeBps = uint16(vm.envOr("FEE_BPS", uint256(0)));
        address owner = vm.envOr("OWNER", msg.sender);

        vm.startBroadcast();
        deployed = new Multisender(owner, feeReceiver, feeBps);
        vm.stopBroadcast();

        console2.log("Multisender deployed:", address(deployed));
        console2.log("Owner:", owner);
        console2.log("Fee receiver:", feeReceiver);
        console2.log("Fee bps:", feeBps);
    }
}
