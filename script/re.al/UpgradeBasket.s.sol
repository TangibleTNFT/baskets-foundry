// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/** 
    @dev To run: 
    forge script script/re.al/UpgradeBasket.s.sol:UpgradeBasket --broadcast --legacy \
    --gas-estimate-multiplier 800 \
    --verify --verifier blockscout --verifier-url https://explorer.re.al//api -vvvv

    @dev To verify manually: 
    forge verify-contract 0xc0030e84741D01a4f9AfC890840dEE8B1833DC08 --chain-id 111188 --watch src/Basket.sol:Basket --verifier blockscout --verifier-url https://explorer.re.al//api
*/

/**
 * @title UpgradeBasket
 * @author Chase Brown
 * @notice This script deploys a new basket imlpementation and uprgades the basketManager upgradeable beacon
 */
contract UpgradeBasket is Script {

    // wallets
    address immutable DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public REAL_RPC_URL = vm.envString("REAL_RPC_URL");

    function setUp() public {
        vm.createSelectFork(REAL_RPC_URL);
    }

    function run() public {

        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // 1. deploy basket
        Basket basket = new Basket();

        // 2. Update beacon (factory owner must call)
        // TODO: set via basketManager.updateBasketImplementation
    

        // log addresses
        console2.log("basket imlpementation address =", address(basket));
    
        vm.stopBroadcast();
    }
}