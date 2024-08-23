// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { BasketManager } from "../../src/BasketManager.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/** 
    @dev To run: 
    forge script script/unreal/UpgradeBasketManager.s.sol:UpgradeBasketManager --broadcast --legacy \
    --gas-estimate-multiplier 200 \
    --verify --verifier blockscout --verifier-url https://unreal.blockscout.com/api -vvvv

    @dev To verify manually: 
    forge verify-contract <CONTRACT_ADDRESS> --chain-id 18233 --watch \ 
    src/BasketManager.sol:BasketManager --verifier blockscout --verifier-url https://unreal.blockscout.com/api
*/

/**
 * @title UpgradeBasketManager
 * @author Chase Brown
 * @notice This script deploys a new basket imlpementation and uprgades the basketManager upgradeable beacon
 */
contract UpgradeBasketManager is Script {

    // wallets
    address immutable DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
    }

    function run() public {

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // 1. deploy basketManager
        BasketManager basketManager = new BasketManager();

        // 2. Update proxy (factory owner must call)
        // TODO: set via basketManager.upgradeToAndCall
    

        // log addresses
        console2.log("basket manager imlpementation address =", address(basketManager));
    
        vm.stopBroadcast();
    }
}