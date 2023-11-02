// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

// tangible contract
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";
import { MockMatrixOracle } from "@tangible/priceOracles/MockMatrixOracle.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "../src/interfaces/IGetNotificationDispatcher.sol";

// local helper contracts
import { VRFCoordinatorV2Mock } from "./utils/VRFCoordinatorV2Mock.sol";
import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title BasketsIntegrationTest
 * @author Chase Brown
 * @notice This test file contains integration tests for the baskets protocol. We import real mumbai addresses of the underlying layer
 *         of smart contracts via MumbaiAddresses.sol.
 */
contract BasketsIntegrationTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public basket;
    BasketManager public basketManager;
    BasketsVrfConsumer public basketVrfConsumer;

    // helper
    VRFCoordinatorV2Mock public vrfCoordinatorMock;

    // tangible mumbai contracts
    FactoryV2 public factoryV2 = FactoryV2(Mumbai_FactoryV2);
    TangibleNFTV2 public realEstateTnft = TangibleNFTV2(Mumbai_TangibleREstateTnft);
    RealtyOracleTangibleV2 public realEstateOracle = RealtyOracleTangibleV2(Mumbai_RealtyOracleTangibleV2);
    MockMatrixOracle public chainlinkRWAOracle = MockMatrixOracle(Mumbai_MockMatrix);
    TNFTMarketplaceV2 public marketplace = TNFTMarketplaceV2(Mumbai_Marketplace);
    TangiblePriceManagerV2 public priceManager = TangiblePriceManagerV2(Mumbai_PriceManager);
    CurrencyFeedV2 public currencyFeed = CurrencyFeedV2(Mumbai_CurrencyFeedV2);
    TNFTMetadata public metadata = TNFTMetadata(Mumbai_TNFTMetadata);
    RentManager public rentManager = RentManager(Mumbai_RentManagerTnft);
    RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Mumbai_RWAPriceNotificationDispatcher);

    // proxies
    ERC1967Proxy public basketManagerProxy;
    ERC1967Proxy public vrfConsumerProxy;

    // ~ Actors and Variables ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4; // NOTE: category owner

    address public rentManagerDepositor = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    uint256 internal portion;

    uint256 internal CREATOR_TOKEN_ID;
    uint256 internal JOE_TOKEN_ID;
    uint256 internal NIK_TOKEN_ID;

    uint256[] internal preMintedTokens;

    // State variables for VRF.
    uint64 internal subId;


    /// @notice Config function for test cases.
    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).owner();

        // vrf config
        vrfCoordinatorMock = new VRFCoordinatorV2Mock(100000, 100000);
        subId = vrfCoordinatorMock.createSubscription();
        vrfCoordinatorMock.fundSubscription(subId, 100 ether);

        // Deploy Basket implementation
        basket = new Basket();

        // Deploy BasketManager
        basketManager = new BasketManager();

        // Deploy proxy for basketManager -> initialize
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2)
            )
        );
        basketManager = BasketManager(address(basketManagerProxy));

        // Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // Deploy proxy for basketsVrfConsumer -> initialize
        vrfConsumerProxy = new ERC1967Proxy(
            address(basketVrfConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                address(factoryV2),
                subId,
                address(vrfCoordinatorMock),
                MUMBAI_VRF_KEY_HASH
            )
        );
        basketVrfConsumer = BasketsVrfConsumer(address(vrfConsumerProxy));

        // set basketVrfConsumer address on basketManager
        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        // add consumer on vrf coordinator 
        vrfCoordinatorMock.addConsumer(subId, address(basketVrfConsumer));

        // updateDepositor for rent manager
        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(TANGIBLE_LABS);

        // set basketManager
        vm.prank(factoryOwner);
        factoryV2.setContract(FactoryV2.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // whitelist basketManager on NotificationDispatcher
        vm.prank(TANGIBLE_LABS); // category owner
        notificationDispatcher.addWhitelister(address(basketManager));
        assertEq(notificationDispatcher.approvedWhitelisters(address(basketManager)), true);

        // set currencyFeed
        vm.prank(factoryOwner);
        factoryV2.setContract(FactoryV2.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        vm.startPrank(ORACLE_OWNER);
        // set tangibleWrapper to be real estate oracle on chainlink oracle.
        chainlinkRWAOracle.setTangibleWrapperAddress(
            address(realEstateOracle)
        );

        // create new item with fingerprint.
        chainlinkRWAOracle.createItem(
            RE_FINGERPRINT_1,  // fingerprint
            200_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        chainlinkRWAOracle.createItem(
            RE_FINGERPRINT_2,  // fingerprint
            500_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        chainlinkRWAOracle.createItem(
            RE_FINGERPRINT_3,  // fingerprint
            600_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        // chainlinkRWAOracle.updateItem( // 1
        //     RE_FINGERPRINT_1,
        //     200_000_000,
        //     0
        // );
        // chainlinkRWAOracle.updateStock(
        //     RE_FINGERPRINT_1,
        //     10
        // );
        // chainlinkRWAOracle.updateItem( // 2
        //     RE_FINGERPRINT_2,
        //     500_000_000,
        //     0
        // );
        // chainlinkRWAOracle.updateStock(
        //     RE_FINGERPRINT_2,
        //     10
        // );
        // chainlinkRWAOracle.updateItem( // 3
        //     RE_FINGERPRINT_3,
        //     600_000_000,
        //     0
        // );
        // chainlinkRWAOracle.updateStock(
        //     RE_FINGERPRINT_3,
        //     10
        // );
        vm.stopPrank();

        vm.startPrank(factoryOwner);
        // add feature to metadata contract
        metadata.addFeatures(
            _asSingletonArrayUint(RE_FEATURE_1),
            _asSingletonArrayString("Beach Homes")
        );
        // add feature to TNFTtype in metadata contract
        metadata.addFeaturesForTNFTType(
            RE_TNFTTYPE,
            _asSingletonArrayUint(RE_FEATURE_1)
        );
        vm.stopPrank();

        // create mint voucher for RE_FP_1 -> goes to creator
        IVoucher.MintVoucher memory voucher1 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_1,                       // fingerprint
            true                                    // sendToVender
        );

        // create mint voucher for RE_FP_2
        IVoucher.MintVoucher memory voucher2 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_2,                       // fingerprint
            true                                    // sendToVender
        );

        // create mint voucher for RE_FP_3
        IVoucher.MintVoucher memory voucher3 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_3,                       // fingerprint
            true                                    // sendToVender
        );

        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1), true);
        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_2), true);
        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_3), true);
        
        // mint fingerprint RE_1 and RE_2
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher1);
        CREATOR_TOKEN_ID = preMintedTokens[0];

        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 1);
        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher2);
        JOE_TOKEN_ID = preMintedTokens[0]; // 2

        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 2);
        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher3);
        NIK_TOKEN_ID = preMintedTokens[0]; // 3

        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 3);

        // transfer token to CREATOR
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, CREATOR, CREATOR_TOKEN_ID);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 2);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(CREATOR), 1);

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, JOE_TOKEN_ID);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(JOE), 1);

        // transfer token to NIK
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, NIK, NIK_TOKEN_ID);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(NIK), 1);

        // Deploy basket
        uint256[] memory features = new uint256[](0);

        // deploy new basket
        vm.startPrank(CREATOR);
        realEstateTnft.approve(address(basketManager), CREATOR_TOKEN_ID);
        (IBasket _basket,) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(CREATOR_TOKEN_ID)
        );
        vm.stopPrank();

        basket = Basket(address(_basket));

        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(basket.balanceOf(CREATOR));
        vm.stopPrank();

        // labels
        vm.label(address(factoryV2), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(chainlinkRWAOracle), "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(basket), "BASKET");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(address(notificationDispatcher), "NOTIFICATION_DISPATCHER");
        vm.label(address(vrfCoordinatorMock), "MOCK_VRF_COORDINATOR");
        vm.label(address(basketVrfConsumer), "BASKET_VRF_CONSUMER");

        vm.label(address(this), "TEST_FILE");
        vm.label(TANGIBLE_LABS, "TANGIBLE_LABS");
        vm.label(JOE, "JOE");
        vm.label(NIK, "NIK");
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");
    }


    // -------
    // Utility
    // -------

    // /// @notice Perform a buy
    // function buy(uint256 tradeAmt) public {

    //     IERC20(WBNB).approve(
    //         address(UNIV2_ROUTER), tradeAmt
    //     );

    //     address[] memory path = new address[](2);

    //     path[0] = WBNB;
    //     path[1] = address(basket);

    //     IUniswapV2Router02(UNIV2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //         tradeAmt,
    //         0,
    //         path,
    //         address(this),
    //         block.timestamp + 300
    //     );
    // }

    // /// @notice Perform a sell
    // function sell(uint256 tradeAmt) public {

    //     IERC20(address(basket)).approve(
    //         address(UNIV2_ROUTER), tradeAmt
    //     );

    //     address[] memory path = new address[](2);

    //     path[0] = address(basket);
    //     path[1] = WBNB;

    //     IUniswapV2Router02(UNIV2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //         tradeAmt,
    //         0,
    //         path,
    //         address(this),
    //         block.timestamp + 300
    //     );
    // }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test. TODO: Add more asserts
    function test_lp_init_state() public {
        
    }


    // ----------
    // Unit Tests
    // ----------


    // ~ Deposit Testing ~

    //
}