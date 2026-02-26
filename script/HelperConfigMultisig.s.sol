// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Script, console2} from "forge-std/Script.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfigMultisig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address entryPoint;
        address usdc;
        address[] accounts;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;
    uint256 constant LOCAL_CHAIN_ID = 31337;
    // Update the burnerWallets to your multiple burner personal wallet you want to test it with!
    address[] burnerWallets = [0x42BB5957F541e150329cF8ff7A52002f746419C4];
    uint256 constant ARBITRUM_MAINNET_CHAIN_ID = 42161;
    uint256 constant ZKSYNC_MAINNET_CHAIN_ID = 324;
    // address constant FOUNDRY_DEFAULT_WALLET = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    address[] anvilDefaultAccounts = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
        0x90F79bf6EB2c4f870365E785982E1f101E93b906,
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
    ];

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getEthSepoliaConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getEthMainnetConfig();
        networkConfigs[ZKSYNC_MAINNET_CHAIN_ID] = getZkSyncConfig();
        networkConfigs[ARBITRUM_MAINNET_CHAIN_ID] = getArbMainnetConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else if (
            localNetworkConfig.accounts.length > 0 && localNetworkConfig.accounts[0] != address(0)
                && localNetworkConfig.accounts[1] != address(0) && localNetworkConfig.accounts[2] != address(0)
                && localNetworkConfig.accounts[3] != address(0) && localNetworkConfig.accounts[4] != address(0)
        ) {
            return networkConfigs[chainId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/
    function getEthMainnetConfig() public view returns (NetworkConfig memory) {
        // This is v7
        return NetworkConfig({
            entryPoint: 0x0000000071727De22E5E9d8BAf0edAc6f37da032,
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            accounts: burnerWallets
        });
        // https://blockscan.com/address/0x0000000071727De22E5E9d8BAf0edAc6f37da032
    }

    function getEthSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789,
            usdc: 0x53844F9577C2334e541Aec7Df7174ECe5dF1fCf0, // Update with your own mock token
            accounts: burnerWallets
        });
    }

    function getArbMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: 0x0000000071727De22E5E9d8BAf0edAc6f37da032,
            usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            accounts: burnerWallets
        });
    }

    function getZkSyncSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: address(0), // There is no entrypoint in zkSync!
            usdc: 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E, // not the real USDC on zksync sepolia
            accounts: burnerWallets
        });
    }

    function getZkSyncConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entryPoint: address(0), // supports native AA, so no entry point needed
            usdc: 0x1d17CBcF0D6D143135aE902365D2E5e2A16538D4,
            accounts: burnerWallets
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (
            localNetworkConfig.accounts.length > 0 && localNetworkConfig.accounts[0] != address(0)
                && localNetworkConfig.accounts[1] != address(0) && localNetworkConfig.accounts[2] != address(0)
                && localNetworkConfig.accounts[3] != address(0) && localNetworkConfig.accounts[4] != address(0)
        ) {
            return localNetworkConfig;
        }

        // deploy mocks
        console2.log("Deploying mocks...");
        vm.startBroadcast(anvilDefaultAccounts[0]);
        EntryPoint entryPoint = new EntryPoint();
        ERC20Mock erc20Mock = new ERC20Mock();
        vm.stopBroadcast();
        console2.log("Mocks deployed!");

        localNetworkConfig =
            NetworkConfig({entryPoint: address(entryPoint), usdc: address(erc20Mock), accounts: anvilDefaultAccounts});
        return localNetworkConfig;
    }
}
