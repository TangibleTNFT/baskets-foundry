// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible imports
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import "../../test/utils/UnrealAddresses.sol";
import "../../test/utils/Utility.sol";

/// @dev To run: forge script script/mumbai/DeployToUnreal.s.sol:DeployToUnreal --fork-url <RPC_URL> --broadcast --verify

/**
 * @title DeployBasketsToUnreal
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Unreal Testnet.
 */
contract DeployToUnreal is Script {

    // ~ Script Configure ~

    // baskets
    Basket public basket;
    BasketManager public basketManager;
    BasketsVrfConsumer public basketVrfConsumer;

    // proxies
    ERC1967Proxy public basketManagerProxy;
    ERC1967Proxy public basketVrfConsumerProxy;

    // wallets
    address immutable MUMBAI_DEPLOYER_ADDRESS = vm.envAddress("MUMBAI_DEPLOYER_ADDRESS");
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");

    address public constant GELATO_VRF_OPERATOR = address(0); // TODO If necessary. Testnet has fulfillRandomnessTestnet which is permissionless

    address deployerAddress;
    uint256 deployerPrivKey;

    address public factoryOwner;

    function setUp() public {

        deployerAddress = MUMBAI_DEPLOYER_ADDRESS;
        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        factoryOwner = IOwnable(Unreal_FactoryV2).owner();

        // 1. deploy basket
        basket = new Basket();

        // 2. Deploy basketManager
        basketManager = new BasketManager();

        // 3. Deploy proxy for basketManager & initialize
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                Unreal_FactoryV2
            )
        );

        // 4. Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // 5. Initialize BasketsVrfConsumer with proxy
        basketVrfConsumerProxy = new ERC1967Proxy(
            address(basketVrfConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                Unreal_FactoryV2,
                GELATO_VRF_OPERATOR,
                18231 // unreal chainId
            )
        );

        // 6. TODO: set basketsVrfConsumer via BasketManager::setBasketsVrfConsumer

        // 7. TODO: set revenueShare via BasketManager::setRevenueShare -> SET REVENUE DISTRIBUTOR

        // 8. TODO: Ensure the new basket manager is added on factory and is whitelister on notification dispatcher
        

        // log addresses
        console2.log("1. BasketManager (proxy)            =", address(basketManagerProxy));
        console2.log("2. BasketManager Implementation     =", address(basketManager));
        
        console2.log("3. BasketVrfConsumer (proxy)        =", address(basketVrfConsumerProxy));
        console2.log("4. BasketVrfConsumer Implementation =", address(basketVrfConsumer));
        
        console2.log("5. Basket Implementation            =", address(basket));
        
        vm.stopBroadcast();
    }

    /**
        == Logs ==
        1. BasketManager (proxy)            = 
        2. BasketManager Implementation     = 
        3. BasketVrfConsumer (proxy)        = 
        4. BasketVrfConsumer Implementation = 
        5. Basket Implementation            = 
    */
}
