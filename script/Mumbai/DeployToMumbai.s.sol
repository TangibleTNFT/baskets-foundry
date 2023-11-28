// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "../../lib/forge-std/src/Script.sol";

// oz imports
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// local contracts
import { Basket } from "../../src/Basket.sol";
import { IBasket } from "../../src/interfaces/IBasket.sol";
import { BasketManager } from "../../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../../src/BasketsVrfConsumer.sol";

// helper contracts
import { VRFCoordinatorV2Mock } from "../../test/utils/VRFCoordinatorV2Mock.sol";
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

    // helper Note: temporary
    VRFCoordinatorV2Mock public vrfCoordinatorMock;

    // proxies
    ERC1967Proxy public basketManagerProxy;
    ERC1967Proxy public basketVrfConsumerProxy;

    // wallets
    address immutable MUMBAI_DEPLOYER_ADDRESS = vm.envAddress("MUMBAI_DEPLOYER_ADDRESS");
    uint256 immutable MUMBAI_DEPLOYER_PRIVATE_KEY = vm.envUint("MUMBAI_DEPLOYER_PRIVATE_KEY");

    // vars
    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks#polygon-matic-mumbai-testnet
    bytes32 public constant MUMBAI_VRF_KEY_HASH = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // 500 gwei

    uint64 internal subId;

    address deployerAddress;
    uint256 deployerPrivKey;

    function setUp() public {

        deployerAddress = MUMBAI_DEPLOYER_ADDRESS;
        deployerPrivKey = MUMBAI_DEPLOYER_PRIVATE_KEY;
    }

    function run() public {

        vm.startBroadcast(deployerPrivKey);

        // 1. Configure vrf
        // deploy mock
        vrfCoordinatorMock = new VRFCoordinatorV2Mock(100000, 100000);
        // create subscription id
        subId = vrfCoordinatorMock.createSubscription();
        // fund subscription
        vrfCoordinatorMock.fundSubscription(subId, 100 ether);

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
                subId,
                address(vrfCoordinatorMock),
                MUMBAI_VRF_KEY_HASH
            )
        );

        // 6. Add consumer to vrf coordinator
        vrfCoordinatorMock.addConsumer(subId, address(basketVrfConsumerProxy));

        // 7. TODO: set basketsVrfConsumer via BasketManager::setBasketsVrfConsumer

        // 8. TODO: set revenueShare via BasketManager::setRevenueShare

        // 9. TODO: Ensure the new basket manager is added on factory and is whitelister on notification dispatcher
        

        // log addresses
        console2.log("1. BasketManager (proxy)            =", address(basketManagerProxy));
        console2.log("2. BasketManager Implementation     =", address(basketManager));
        
        console2.log("3. BasketVrfConsumer (proxy)        =", address(basketVrfConsumerProxy));
        console2.log("4. BasketVrfConsumer Implementation =", address(basketVrfConsumer));
        
        console2.log("5. Mock Vrf Coordinator             =", address(vrfCoordinatorMock));
        console2.log("6. Basket Implementation            =", address(basket));
        
        vm.stopBroadcast();
    }

    /**
        == Logs ==
        1. Mock Vrf Coordinator: 0x19d3746C662973E17C2a8658D958a977fbfdeb29
        2. Basket Implementation: 0x86892455EB3F49307607aA006c15D11Af0ac7aA4
        3. BasketManager Implementation: 0x1FA8f797A5D6a56aee856850aa701157EA53f57E
        4. BasketManager Proxy: 0x1e44E0a4B8596E47E291f868A0485864AC7eE869
        5. BasketVrfConsumer Implementation: 0x36b6240FD63D5A4fb095AbF7cC8476659C76071C
        6. BasketVrfConsumer Proxy: 0x192ab3Dfee4e087C4F5a5cE54F3053fe4D0C277D
    */
}
