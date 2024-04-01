// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/// @dev To run: forge script script/unreal/RebaseBaskets.s.sol:RebaseBaskets --broadcast --legacy

/**
 * @title RebaseBaskets
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Unreal Testnet.
 */
contract RebaseBaskets is Script {

    // ~ Script Configure ~

    // baskets contracts
    BasketManager public unrealBasketManager = BasketManager(Unreal_BasketManager);
    BasketsVrfConsumer public unrealBasketsVrfConsumer = BasketsVrfConsumer(Unreal_BasketVrfConsumer);

    FactoryV2 public factoryV2 = FactoryV2(Unreal_FactoryV2);
    RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Unreal_RWAPriceNotificationDispatcher);

    // wallets
    uint256 immutable DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    uint256 deployerPrivKey;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);

        deployerPrivKey = DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. TODO: set basketsVrfConsumer via BasketManager::setBasketsVrfConsumer

        unrealBasketManager.setBasketsVrfConsumer(address(unrealBasketsVrfConsumer));

        // 2. TODO: set revenueShare via BasketManager::setRevenueShare -> SET REVENUE DISTRIBUTOR

        // 3. TODO: Ensure the new basket manager is added on factory and is whitelister on notification dispatcher

        factoryV2.setContract(FactoryV2.FACT_ADDRESSES.BASKETS_MANAGER, address(unrealBasketManager));

        notificationDispatcher.addWhitelister(address(unrealBasketManager));
        
        vm.stopBroadcast();
    }
}
