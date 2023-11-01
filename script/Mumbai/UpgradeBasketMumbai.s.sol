// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";

// helper contracts
import { VRFCoordinatorV2Mock } from "../../test/utils/VRFCoordinatorV2Mock.sol";
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

/**
 * @title UpgradeBasketMumbai
 * @author Chase Brown
 * @notice This script deploys a new Basket implementation and upgrades the proxy.
 */
contract UpgradeBasketMumbai is Script {

    // ~ Script Configure ~

    // baskets
    Basket public basket;

    // wallets
    address immutable MUMBAI_DEPLOYER_ADDRESS = vm.envAddress("MUMBAI_DEPLOYER_ADDRESS");
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");

    // vars
    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks#polygon-matic-mumbai-testnet
    bytes32 public constant MUMBAI_VRF_KEY_HASH = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // 500 gwei

    address deployerAddress;
    uint256 deployerPrivKey;

    function setUp() public {

        deployerAddress = MUMBAI_DEPLOYER_ADDRESS;
        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // deploy new contract
        // upgrade implementation on proxy

        vm.stopBroadcast();
    }
}
