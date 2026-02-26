// SPDX-License-Identifier:MIT SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import {Script} from "forge-std/Script.sol";
import {HelperConfigMultisig} from "./HelperConfigMultisig.s.sol";
import {MinimalAccountMultiSig} from "../src/ethereum/MinimalAccountMultiSig.sol";

contract DeployMinimalAccountMultisig is Script {
    uint256 minThreshold = 3;

    function run() public {
        deployMinimalAccountMultisig();
    }

    function deployMinimalAccountMultisig() public returns (HelperConfigMultisig, MinimalAccountMultiSig) {
        HelperConfigMultisig helperConfig = new HelperConfigMultisig();
        HelperConfigMultisig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.accounts[0]);
        MinimalAccountMultiSig minimalAccountMultisig =
            new MinimalAccountMultiSig(config.entryPoint, config.accounts, minThreshold);
        vm.stopBroadcast();
        return (helperConfig, minimalAccountMultisig);
    }
}
