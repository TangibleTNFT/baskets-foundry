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
import "../../test/utils/MumbaiAddresses.sol";
import "../../test/utils/Utility.sol";

/// @dev To run: forge script script/mumbai/DeployToMumbai.s.sol:DeployToMumbai --fork-url <RPC_URL> --broadcast --verify

/**
 * @title DeployBasketsToMumbai
 * @author Chase Brown
 * @notice This script deploys a new instance of the baskets protocol (in full) to the Mumbai Testnet.
 */
contract DeployToMumbai is Script {

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

        factoryOwner = IOwnable(Mumbai_FactoryV2).owner();

        // 1. deploy basket
        basket = new Basket();

        // 2. Deploy basketManager
        basketManager = new BasketManager();

        // 3. Deploy proxy for basketManager & initialize
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                Mumbai_FactoryV2
            )
        );

        // 4. Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // 5. Initialize BasketsVrfConsumer with proxy
        basketVrfConsumerProxy = new ERC1967Proxy(
            address(basketVrfConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                Mumbai_FactoryV2,
                GELATO_VRF_OPERATOR
            )
        );

        // 6. TODO: Verify tesnet -> If NOT MUMBAI, Update GelatoVRFConsumerBase AND BasketManager

        // 7. TODO: set basketsVrfConsumer via BasketManager::setBasketsVrfConsumer

        // 8. TODO: set revenueShare via BasketManager::setRevenueShare -> SET REVENUE DISTRIBUTOR

        // 9. TODO: Ensure the new basket manager is added on factory and is whitelister on notification dispatcher
        

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
        1. BasketManager (proxy)            = 0x7B6bb198e637073089214a46cC95430ACe572C0A
        2. BasketManager Implementation     = 0x08c2a8c0A86A125cfAD0a2De3F50651237E4dE87
        3. BasketVrfConsumer (proxy)        = 0xa0e1eDED3Bfe0D5A19ba83e0bC66DE267D7BAE32
        4. BasketVrfConsumer Implementation = 0xDFA3E667E30F0b086a368F8bAA28602783746eE7
        5. Basket Implementation            = 0xC19895627fB8e480Dc97732522e12E6e0A1770ec
    */
}
