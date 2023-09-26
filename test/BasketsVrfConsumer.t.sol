// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketsManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";

import { VRFCoordinatorV2Mock } from "./utils/VRFCoordinatorV2Mock.sol";
import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

// tangible contract imports
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";


contract BasketsVrfConsumerTest is Utility {

    // contracts
    Basket public basket;
    BasketManager public basketManager;
    BasketsVrfConsumer public basketVrfConsumer;
    VRFCoordinatorV2Mock public vrfCoordinatorMock;

    FactoryProvider public factoryProvider;
    FactoryV2 public factory;

    // Actors
    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible Labs Multisig")));

    // other vars
    bytes32 public constant KEY_HASH = bytes32(bytes("VRF COORDINATOR KEY HASH"));
    uint64 public subId;


    function setUp() public {

        //vm.createSelectFork(MUMBAI_RPC_URL);

        // Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // vrf config
        // Note: address(this) is the admin
        vrfCoordinatorMock = new VRFCoordinatorV2Mock(100000, 100000);
        subId = vrfCoordinatorMock.createSubscription();
        vrfCoordinatorMock.fundSubscription(subId, 100 ether);

        // Deploy implementation basket
        basket = new Basket();

        // Deploy Factory
        factory = new FactoryV2(
            address(MUMBAI_USDC),
            TANGIBLE_LABS
        );

        // Deploy Factory Provider
        factoryProvider = new FactoryProvider();
        factoryProvider.initialize(address(factory));

        // Deploy basketManager
        basketManager = new BasketManager(
            address(basket),
            address(factoryProvider)
        );

        // Initialize Basket
        uint256[] memory features = new uint256[](0);
        vm.prank(address(basketManager));
        basket.initialize(
            "Tangible Basket Token",
            "TBT",
            address(factoryProvider),
            1,
            address(MUMBAI_USDC),
            features,
            address(this)
        );

        basketManager.addBasket(address(basket));

        // Initialize BasketsVrfConsumer
        vm.prank(PROXY);
        basketVrfConsumer.initialize(
            address(factoryProvider),
            subId,
            address(vrfCoordinatorMock),
            KEY_HASH
        );

        // config
        factory.setContract(FactoryV2.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));
        vrfCoordinatorMock.addConsumer(subId, address(basketVrfConsumer));
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        // labels
        vm.label(address(basket), "BASKET");
        
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_basketsVrfConsumer_init_state() public {
        assertEq(basketVrfConsumer.subId(), 1);
        assertEq(basketVrfConsumer.keyHash(), KEY_HASH);
        assertEq(basketVrfConsumer.factoryProvider(), address(factoryProvider));
        assertEq(basketVrfConsumer.vrfCoordinator(), address(vrfCoordinatorMock));
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ makeRequestForRandomWords ~

    /// @notice Verifies correct state changes when makeRequestForRandomWords() is executed.
    function test_basketsVrfConsumer_makeRequestForRandomWords() public {
        // Execute makeRequestForRandomWords()
        vm.prank(address(basket));
        uint256 requestId = basketVrfConsumer.makeRequestForRandomWords();

        // Post-state check
        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fullfilled(requestId), false);
    }

    // ~ fulfillRandomWords ~

    /// @notice Verifies correct state changes when fulfillRandomWords() is executed.
    function test_basketsVrfConsumer_fulfillRandomWords() public {
        vm.prank(address(basket));
        uint256 requestId = basketVrfConsumer.makeRequestForRandomWords();

        // Pre-state check
        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fullfilled(requestId), false);

        // Execute fulfillRandomWords()
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(requestId, _asSingletonArrayUint(999));

        // Post-state check
        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fullfilled(requestId), true);
    }

}