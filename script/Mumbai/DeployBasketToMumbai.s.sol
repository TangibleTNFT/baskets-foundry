// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";

// helper contracts
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

/**
 * @title DeployBasketMumbai
 * @author Chase Brown
 * @notice This script deploys a new Basket implementation.
 */
contract DeployBasketToMumbai is Script {

    // ~ Script Configure ~

    // baskets
    Basket public basket;

    // wallets
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");

    uint256 deployerPrivKey;

    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);

        deployerPrivKey = DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. deploy new contract
        basket = new Basket();

        // 2. upgrade implementation on proxy
        // todo: Do manually

        // log addresses

        console2.log("Basket address:", address(basket));

        vm.stopBroadcast();
    }
}
