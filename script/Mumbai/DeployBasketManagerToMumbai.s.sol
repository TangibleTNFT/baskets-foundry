// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// local contracts
import { BasketManager } from "../../src/BasketManager.sol";

// helper contracts
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

/**
 * @title DeployBasketManagerMumbai
 * @author Chase Brown
 * @notice This script deploys a new BasketManager implementation.
 */
contract DeployBasketManagerToMumbai is Script {

    // ~ Script Configure ~

    // baskets
    BasketManager public basketManager;

    // wallets
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");
    string public MUMBAI_RPC_URL = vm.envString("MUMBAI_RPC_URL");

    uint256 deployerPrivKey;

    function setUp() public {
        vm.createSelectFork(MUMBAI_RPC_URL);

        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. deploy new contract
        basketManager = new BasketManager();

        // 2. upgrade implementation on proxy
        // todo: Do manually

        // log addresses

        console2.log("BasketManager address:", address(basketManager));

        vm.stopBroadcast();
    }
}
