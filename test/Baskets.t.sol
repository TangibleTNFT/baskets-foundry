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
import { BasketManager } from "../src/BasketsManager.sol";
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

    /// @notice This method adds feature metadata to a tokenId on a tnft contract
    function _addFeatureToCategory(address _tnft, uint256 _tokenId, uint256[] memory _features) public {
        vm.prank(TANGIBLE_LABS);
        // add feature to tnft contract
        ITangibleNFTExt(_tnft).addMetadata(
            _tokenId,
            _features
        );
    }

    /// @notice This method runs through the same USDValue logic as the Basket::depositTNFT
    function _getUsdValueOfNft(address _tnft, uint256 _tokenId) internal returns (uint256 UsdValue) {
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        //emit log_named_uint("fingerprint", fingerprint);

        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = realEstateOracle.marketPriceNativeCurrency(fingerprint);
        emit log_named_uint("market value", value); // 500_000_000
        //emit log_named_uint("currencyNum", currencyNum);

        // Fetch the string ISO code for currency
        string memory currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));
        //emit log_named_string("currencyAlpha", currency);

        // get decimal representation of property value
        uint256 oracleDecimals = realEstateOracle.decimals();
        //emit log_named_uint("oracle decimals", oracleDecimals);
        
        // ~ get USD Exchange rate ~

        // fetch price feed contract for native currency
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currency);
        emit log_named_address("address of priceFeed", address(priceFeed));

        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();
        emit log_named_uint("Price of GBP/USD", uint(price));

        // get decimal representation of exchange rate
        uint256 priceDecimals = priceFeed.decimals();
        //emit log_named_uint("price feed decimals", priceDecimals);
 
        // ~ get USD Value of property ~

        // calculate total USD value of property
        UsdValue = (uint(price) * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
        emit log_named_uint("USD Value", UsdValue); // 650_000_000000000000000000 (18)

    }

    /// @notice Helper function for creating items and minting to a designated address.
    function _createItemAndMint(address tnft, uint256 _sellAt, uint256 _stock, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        require(_mintCount >= _stock, "mint count must be gt stock");

        vm.startPrank(ORACLE_OWNER);
        // create new item with fingerprint.
        chainlinkRWAOracle.createItem(
            _fingerprint, // fingerprint
            _sellAt,      // weSellAt
            0,            // lockedAmount
            _stock,       // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        vm.stopPrank();

        vm.prank(TANGIBLE_LABS);
        ITangibleNFTExt(tnft).addFingerprints(_asSingletonArrayUint(_fingerprint));

        return _mintToken(tnft, _mintCount, _fingerprint, _receiver);
    }

    /// @notice Helper function for minting to a designated address.
    function _mintToken(address tnft, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        uint256 preBal = IERC721(tnft).balanceOf(TANGIBLE_LABS);

        // create mint voucher for RE_FP_1
        IVoucher.MintVoucher memory voucher = IVoucher.MintVoucher(
            ITangibleNFT(tnft),  // token
            _mintCount,          // mintCount
            0,                   // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,       // vendor
            address(0),          // buyer
            _fingerprint,        // fingerprint
            true                 // sendToVender
        );

        // mint token
        vm.prank(TANGIBLE_LABS);
        uint256[] memory tokenIds = factoryV2.mint(voucher);
        assertEq(IERC721(tnft).balanceOf(TANGIBLE_LABS), preBal + _mintCount);

        // transfer token to NIK
        for (uint256 i; i < _mintCount; ++i) {
            vm.prank(TANGIBLE_LABS);
            IERC721(tnft).transferFrom(TANGIBLE_LABS, _receiver, tokenIds[i]);
        }
        assertEq(IERC721(tnft).balanceOf(TANGIBLE_LABS), preBal);

        return tokenIds;
    }

    /// @notice This helper method is used to calculate amount taken for fee upon a deposit.
    function _calculateFeeAmount(uint256 _amount) internal view returns (uint256) {
        return (_amount * basket.depositFee()) / 100_00;
    }

    /// @notice This helper method is used to fetch amount received after deposit post fee.
    function _calculateAmountAfterFee(uint256 _amount) internal view returns (uint256) {
        return (_amount - _calculateFeeAmount(_amount));
    }

    /// @notice This helper method is used to execute a mock callback from the vrf coordinator.
    function _mockVrfCoordinatorResponse(uint256 _requestId, uint256 _randomWord) internal {
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(
            _requestId, // requestId
            _asSingletonArrayUint(_randomWord) // random word
        );
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test. TODO: Add more asserts
    function test_baskets_init_state() public {
        // verify realEstateTnft
        assertEq(realEstateTnft.tokensFingerprint(JOE_TOKEN_ID), RE_FINGERPRINT_2); // Joe's tokenId

        // verify factoryV2 has correct priceManager
        assertEq(address(factoryV2.priceManager()), address(priceManager));

        // verify priceManager has oracle set
        assertEq(address(IPriceManagerExt(address(priceManager)).oracleForCategory(realEstateTnft)), address(realEstateOracle));

        // verify notification dispatcher state
        assertEq(notificationDispatcher.whitelistedReceiver(address(basket)), true);

        // verify BasketsVrfConsumer initial state
        assertEq(basketVrfConsumer.subId(), subId);
        assertEq(basketVrfConsumer.keyHash(), MUMBAI_VRF_KEY_HASH);
        assertEq(basketVrfConsumer.requestConfirmations(), 20);
        assertEq(basketVrfConsumer.callbackGasLimit(), 50_000);
        assertEq(basketVrfConsumer.vrfCoordinator(), address(vrfCoordinatorMock));
    }


    // ----------
    // Unit Tests
    // ----------


    // ~ Deposit Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT_single() public {
        uint256 preInCounter = basket.inCounter();
        uint256 preOutCounter = basket.outCounter();

        // ~ Pre-state check ~

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.inCounter(), preInCounter);
        assertEq(basket.outCounter(), preOutCounter);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // emit deposit logic 
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 quote = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);

        // ~ Execute a deposit ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", basket.getSharePrice());

        // ~ Post-state check ~

        //uint256 feeTaken = _calculateFeeAmount(quote);
        uint256 amountAfterFee = _calculateAmountAfterFee(quote);

        assertWithinPrecision(
            (basket.balanceOf(JOE) * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(quote, usdValue);

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), amountAfterFee);
        assertEq(basket.balanceOf(JOE), amountAfterFee);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.inCounter(), preInCounter + 1);
        assertEq(basket.outCounter(), preOutCounter);

        (address _tnft, uint256 _tokenId,) = basket.fifoTracker(basket.inCounter());
        assertEq(_tnft, address(realEstateTnft));
        assertEq(_tokenId, JOE_TOKEN_ID);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_ID);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_2);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], JOE_TOKEN_ID);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT_multiple() public {
        uint256 preInCounter = basket.inCounter();
        uint256 preOutCounter = basket.outCounter();

        // ~ Pre-state check ~

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(NIK), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(0));

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), false);
        assertEq(basket.inCounter(), preInCounter);
        assertEq(basket.outCounter(), preOutCounter);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        //uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        //uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);

        //uint256 feeTaken_Joe = _calculateFeeAmount(basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID));
        uint256 amountAfterFee_Joe = _calculateAmountAfterFee(basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID));

        // ~ Joe deposits TNFT ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // ~ Nik deposits TNFT ~

        //uint256 feeTaken_Nik = _calculateFeeAmount(basket.getQuoteIn(address(realEstateTnft), NIK_TOKEN_ID));
        uint256 amountAfterFee_Nik = _calculateAmountAfterFee(basket.getQuoteIn(address(realEstateTnft), NIK_TOKEN_ID));

        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), NIK_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("NIK's BASKET BALANCE", basket.balanceOf(NIK));
        emit log_named_uint("SHARE PRICE", basket.getSharePrice());

        // ~ Post-state check ~

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(NIK), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 2);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), amountAfterFee_Joe);
        assertEq(basket.balanceOf(NIK), amountAfterFee_Nik);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);
        assertEq(basket.inCounter(), preInCounter + 2);
        assertEq(basket.outCounter(), preOutCounter);

        (address _tnft, uint256 _tokenId,) = basket.fifoTracker(basket.inCounter() - 1);
        assertEq(_tnft, address(realEstateTnft));
        assertEq(_tokenId, JOE_TOKEN_ID);

        (_tnft, _tokenId,) = basket.fifoTracker(basket.inCounter());
        assertEq(_tnft, address(realEstateTnft));
        assertEq(_tokenId, NIK_TOKEN_ID);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_ID);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_2);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, NIK_TOKEN_ID);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_3);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        uint256[] memory tokenidLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenidLib.length, 2);
        assertEq(tokenidLib[0], JOE_TOKEN_ID);
        assertEq(tokenidLib[1], NIK_TOKEN_ID);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT_feature() public {
        uint256[] memory features = new uint256[](1);
        features[0] = RE_FEATURE_1;

        // create initial token for deployment
        uint256[] memory tokenIds = _mintToken(
            address(realEstateTnft),
            1,
            RE_FINGERPRINT_1,
            address(this)
        );
        uint256 tokenId = tokenIds[0];

        // add feature

        Basket _basket = new Basket();

        // add feature to initial TNFT
        _addFeatureToCategory(address(realEstateTnft), tokenId, _asSingletonArrayUint(RE_FEATURE_1));

        // create new basket with feature
        realEstateTnft.approve(address(basketManager), tokenId);
        (IBasket tbasket,) = basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(tokenId)
        );

        _basket = Basket(address(tbasket));

        // Pre-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);

        // Execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(_basket), JOE_TOKEN_ID);
        vm.expectRevert("Token incompatible");
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);

        // add feature to TNFT
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_1));

        // Execute a deposit
        vm.startPrank(JOE);
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_depositTNFT_feature_multiple() public {
        // create initial token for deployment
        uint256[] memory tokenIds = _mintToken(
            address(realEstateTnft),
            1,
            RE_FINGERPRINT_1,
            address(this)
        );
        uint256 tokenId = tokenIds[0];

        // create features
        uint256[] memory featuresToAdd = new uint256[](3);
        featuresToAdd[0] = RE_FEATURE_2;
        featuresToAdd[1] = RE_FEATURE_3;
        featuresToAdd[2] = RE_FEATURE_4;

        string[] memory descriptionsToAdd = new string[](3);
        descriptionsToAdd[0] = "Desc for feat 2";
        descriptionsToAdd[1] = "Desc for feat 3";
        descriptionsToAdd[2] = "Desc for feat 4";
     
        // add more features to tnftType
        vm.startPrank(factoryOwner);
        metadata.addFeatures(featuresToAdd, descriptionsToAdd);
        metadata.addFeaturesForTNFTType(RE_TNFTTYPE, featuresToAdd);
        vm.stopPrank();

        // features to add to basket initially
        featuresToAdd = new uint256[](3);
        featuresToAdd[0] = RE_FEATURE_1;
        featuresToAdd[1] = RE_FEATURE_2;
        featuresToAdd[2] = RE_FEATURE_3;

        // create new basket with feature
        Basket _basket = new Basket();

        // add features to initial TNFT
        _addFeatureToCategory(address(realEstateTnft), tokenId, featuresToAdd);

        // create new basket with feature
        realEstateTnft.approve(address(basketManager), tokenId);
        (IBasket tbasket,) = basketManager.deployBasket(
            "Tangible Basket Token1",
            "TBT1",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            featuresToAdd,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(tokenId)
        );

        _basket = Basket(address(tbasket));

        // Pre-state check
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), false);
        assertEq(_basket.featureSupported(RE_FEATURE_1), true);
        assertEq(_basket.featureSupported(RE_FEATURE_2), true);
        assertEq(_basket.featureSupported(RE_FEATURE_3), true);

        // Try to execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(_basket), JOE_TOKEN_ID);
        vm.expectRevert("Token incompatible");
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 1.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        // add feature 1 to TNFT
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_1));

        // Try to execute a deposit
        vm.startPrank(JOE);
        vm.expectRevert("Token incompatible");
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 2.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        // add feature 2 to TNFT
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_2));

        // Try to execute a deposit
        vm.startPrank(JOE);
        vm.expectRevert("Token incompatible");
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 3.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        // add feature 3 to TNFT
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_3));

        // Try to execute a deposit
        vm.startPrank(JOE);
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 4.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), false);

        // add all featurs to TNFT 2
        _addFeatureToCategory(address(realEstateTnft), NIK_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_1));
        _addFeatureToCategory(address(realEstateTnft), NIK_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_2));
        _addFeatureToCategory(address(realEstateTnft), NIK_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_3));
        _addFeatureToCategory(address(realEstateTnft), NIK_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_4));
        assertEq(_basket.featureSupported(RE_FEATURE_4), false);

        // Try to execute a deposit
        vm.startPrank(NIK);
        realEstateTnft.approve(address(_basket), NIK_TOKEN_ID);
        _basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 5.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(_basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::batchDepositTNFT() is executed.
    function test_baskets_batchDepositTNFT() public {

        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preSupply = basket.totalSupply();

        uint256 amountTNFTs = 3;

        uint256[] memory tokenIds = _mintToken(address(realEstateTnft), amountTNFTs, RE_FINGERPRINT_2, JOE);
        address[] memory tnfts = new address[](amountTNFTs);
        for (uint256 i; i < tokenIds.length; ++i) {
            tnfts[i] = address(realEstateTnft);
        }

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + amountTNFTs);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), preSupply);

        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), false);
            assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenIds[i]), address(0));
            assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenIds[i]), address(0));
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, preBalBasket);

        // Execute a batch deposit
        vm.startPrank(JOE);
        for (uint256 i; i < amountTNFTs; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        uint256[] memory shares = basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", basket.getSharePrice());

        uint256 totalShares;
        for (uint i; i < amountTNFTs; ++i) {
            totalShares += shares[i];
        }

        // Post-state check

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + amountTNFTs);

        assertEq(basket.balanceOf(JOE), totalShares);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(JOE));
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
            assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenIds[i]), address(basket));
            assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenIds[i]), address(basket));
        }

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, preBalBasket + amountTNFTs);

        for (uint256 i; i < deposited.length; ++i) { // skip initial token
            assertEq(deposited[i].tokenId, tokenIds[i]);
            assertEq(deposited[i].fingerprint, RE_FINGERPRINT_2);
        }

        // Try to call batchDepositNFT with diff size arrays -> revert
        tokenIds = new uint256[](1);
        tnfts = new address[](2);

        vm.expectRevert("Arrays not same size");
        basket.batchDepositTNFT(tnfts, tokenIds);
    }


    // ~ Redeem Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed.
    function test_baskets_redeemTNFT_single() public {
        uint256 preInCounter = basket.inCounter();
        uint256 preOutCounter = basket.outCounter();

        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);

        uint256 quote = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);

        // ~ Config ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // ~ Pre-state check ~

        uint256 feeTaken = _calculateFeeAmount(quote);
        uint256 amountAfterFee = _calculateAmountAfterFee(quote);

        assertEq(quote, amountAfterFee + feeTaken);

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), amountAfterFee);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.inCounter(), preInCounter + 1);
        assertEq(basket.outCounter(), preOutCounter);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);

        // ~ State changes ~

        // Joe performs a redeem with 0 budget -> revert
        vm.prank(JOE);
        vm.expectRevert("Insufficient budget");
        basket.redeemTNFT(0);

        // Joe performs a redeem with over balance -> revert
        vm.prank(JOE);
        vm.expectRevert("Insufficient balance");
        basket.redeemTNFT(amountAfterFee + 1);

        // Joe performs a redeem -> success
        vm.prank(JOE);
        basket.redeemTNFT(amountAfterFee);

        // ~ Post-state check ~

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.inCounter(), preInCounter + 1);
        assertEq(basket.outCounter(), preOutCounter + 1);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed for multiple TNFTs.
    function test_baskets_redeemTNFT_multiple() public {
        uint256 preInCounter = basket.inCounter();
        uint256 preOutCounter = basket.outCounter();

        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preBalNik = realEstateTnft.balanceOf(NIK);

        // ~ Config ~

        // Joe deposits token

        uint256 quote_Joe = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 amountAfterFee_Joe = _calculateAmountAfterFee(quote_Joe);

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Nik deposits token

        uint256 quote_Nik = basket.getQuoteIn(address(realEstateTnft), NIK_TOKEN_ID);
        uint256 amountAfterFee_Nik = _calculateAmountAfterFee(quote_Nik);

        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), NIK_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe - 1);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 2);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), amountAfterFee_Joe);
        assertEq(basket.balanceOf(NIK), amountAfterFee_Nik);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);
        assertEq(basket.inCounter(), preInCounter + 2);
        assertEq(basket.outCounter(), preOutCounter);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_ID);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_2);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, NIK_TOKEN_ID);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_3);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 2);
        assertEq(tokenIdLib[0], JOE_TOKEN_ID);
        assertEq(tokenIdLib[1], NIK_TOKEN_ID);

        // ~ Joe performs a redeem ~

        emit log_string("REDEEM 1");

        // NOTE: cheaper budget, redeems cheaper token first which is Joe's token
        vm.startPrank(JOE);
        basket.redeemTNFT(basket.balanceOf(JOE));
        vm.stopPrank();

        // This redeem generates a request to vrf. Mock response.
        _mockVrfCoordinatorResponse(
            basketVrfConsumer.outstandingRequest(address(basket)),
            100
        );

        // ~ Post-state check 1 ~

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(basket));

        assertGt(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), amountAfterFee_Nik);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);
        assertEq(basket.inCounter(), preInCounter + 2);
        assertEq(basket.outCounter(), preOutCounter + 1);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, NIK_TOKEN_ID);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_3);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], NIK_TOKEN_ID);

        // Joe sends extra tokens to Nik
        vm.startPrank(JOE);
        basket.transfer(NIK, basket.balanceOf(JOE));
        vm.stopPrank();

        assertEq(basket.balanceOf(JOE), 0);
        assertGt(basket.balanceOf(NIK), amountAfterFee_Nik);

        // ~ Nik performs a redeem ~

        emit log_string("REDEEM 2");

        vm.startPrank(NIK);
        basket.redeemTNFT(basket.balanceOf(NIK));
        vm.stopPrank();

        // ~ Post-state check 2 ~

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(0));

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), false);
        assertEq(basket.inCounter(), preInCounter + 2);
        assertEq(basket.outCounter(), preOutCounter + 2);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    /// @notice This test verifies the implementation of the First-In-First-Out redeem method.
    // function test_baskets_redeemTNFT_fifo() public {
    //     uint256 preInCounter = basket.inCounter();
    //     uint256 preOutCounter = basket.outCounter();
     
    //     // ~ config ~

    //     uint256 totalTokens = 6;

    //     address[] memory batchTnftArr = new address[](totalTokens);
    //     uint256[] memory batchTokenIdArr = new uint256[](totalTokens);

    //     // create multiple tokens with specific prices

    //     // Mint Alice token
    //     uint256[] memory tokenIds = _createItemAndMint(
    //         address(realEstateTnft),
    //         100_000_000,
    //         1,
    //         1, // mintCount
    //         1, // fingerprint
    //         ALICE
    //     );
    //     uint256 firstTokenId = tokenIds[0];
    //     batchTokenIdArr[0] = firstTokenId;
    //     batchTnftArr[0] = address(realEstateTnft);

    //     // Mint Alice token
    //     tokenIds = _createItemAndMint(
    //         address(realEstateTnft),
    //         100_000_000,
    //         1,
    //         1,
    //         2,
    //         ALICE
    //     );
    //     uint256 secondTokenId = tokenIds[0];
    //     batchTokenIdArr[1] = secondTokenId;
    //     batchTnftArr[1] = address(realEstateTnft);

    //     // Mint Alice token
    //     tokenIds = _createItemAndMint(
    //         address(realEstateTnft),
    //         100_000_000,
    //         1,
    //         1,
    //         3,
    //         ALICE
    //     );
    //     uint256 thirdTokenId = tokenIds[0];
    //     batchTokenIdArr[2] = thirdTokenId;
    //     batchTnftArr[2] = address(realEstateTnft);

    //     // Mint Alice token
    //     tokenIds = _createItemAndMint(
    //         address(realEstateTnft),
    //         100_000_000,
    //         1,
    //         1,
    //         4,
    //         ALICE
    //     );
    //     uint256 fourthTokenId = tokenIds[0];
    //     batchTokenIdArr[3] = fourthTokenId;
    //     batchTnftArr[3] = address(realEstateTnft);

    //     // Mint Alice token
    //     tokenIds = _createItemAndMint(
    //         address(realEstateTnft),
    //         100_000_000,
    //         1,
    //         1,
    //         5,
    //         ALICE
    //     );
    //     uint256 fifthTokenId = tokenIds[0];
    //     batchTokenIdArr[4] = fifthTokenId;
    //     batchTnftArr[4] = address(realEstateTnft);

    //     // Mint Alice token
    //     tokenIds = _createItemAndMint(
    //         address(realEstateTnft),
    //         100_000_000,
    //         1,
    //         1,
    //         6,
    //         ALICE
    //     );
    //     uint256 sixthTokenId = tokenIds[0];
    //     batchTokenIdArr[5] = sixthTokenId;
    //     batchTnftArr[5] = address(realEstateTnft);

    //     assertEq(realEstateTnft.balanceOf(ALICE), totalTokens);
     
    //     // batchDeposit all tokens
    //     vm.startPrank(ALICE);
    //     for (uint256 i; i < totalTokens; ++i) {
    //         realEstateTnft.approve(address(basket), batchTokenIdArr[i]);
    //     }
    //     basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);
    //     vm.stopPrank();

    //     // ~ Pre-state check ~

    //     assertEq(realEstateTnft.balanceOf(ALICE), 0);
    //     assertEq(realEstateTnft.balanceOf(address(basket)), totalTokens);
    //     assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
    //     assertEq(basket.inCounter(), preInCounter + totalTokens);
    //     assertEq(basket.outCounter(), preOutCounter);

    //     Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
    //     assertEq(deposited.length, totalTokens);

    //     assertEq(realEstateTnft.ownerOf(firstTokenId),  address(basket));
    //     assertEq(realEstateTnft.ownerOf(secondTokenId), address(basket));
    //     assertEq(realEstateTnft.ownerOf(thirdTokenId),  address(basket));
    //     assertEq(realEstateTnft.ownerOf(fourthTokenId), address(basket));
    //     assertEq(realEstateTnft.ownerOf(fifthTokenId),  address(basket));
    //     assertEq(realEstateTnft.ownerOf(sixthTokenId),  address(basket));

    //     IBasket.RedeemData memory redeemable;
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, firstTokenId);

    //     // ~ Execute redeem ~

    //     vm.startPrank(ALICE);
    //     basket.redeemTNFT(basket.balanceOf(ALICE)); // should redeem firstTokenId
    //     vm.stopPrank();

    //     // ~ Post-state check 1 ~

    //     assertEq(realEstateTnft.ownerOf(firstTokenId), ALICE);
    //     assertEq(basket.outCounter(), preOutCounter + 1);
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, secondTokenId);

    //     // ~ Execute redeem ~

    //     vm.startPrank(ALICE);
    //     basket.redeemTNFT(basket.balanceOf(ALICE)); // should redeem secondTokenId
    //     vm.stopPrank();

    //     // ~ Post-state check 2 ~

    //     assertEq(realEstateTnft.ownerOf(secondTokenId), ALICE);
    //     assertEq(basket.outCounter(), preOutCounter + 2);
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, thirdTokenId);

    //     // ~ Execute redeem ~

    //     vm.startPrank(ALICE);
    //     basket.redeemTNFT(basket.balanceOf(ALICE)); // should redeem thirdTokenId
    //     vm.stopPrank();

    //     // ~ Post-state check 3 ~

    //     assertEq(realEstateTnft.ownerOf(thirdTokenId), ALICE);
    //     assertEq(basket.outCounter(), preOutCounter + 3);
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, fourthTokenId);

    //     // ~ Execute redeem ~

    //     vm.startPrank(ALICE);
    //     basket.redeemTNFT(basket.balanceOf(ALICE)); // should redeem fourthTokenId
    //     vm.stopPrank();

    //     // ~ Post-state check 4 ~

    //     assertEq(realEstateTnft.ownerOf(fourthTokenId), ALICE);
    //     assertEq(basket.outCounter(), preOutCounter + 4);
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, fifthTokenId);

    //     // ~ Execute redeem ~

    //     vm.startPrank(ALICE);
    //     basket.redeemTNFT(basket.balanceOf(ALICE)); // should redeem fifthTokenId
    //     vm.stopPrank();

    //     // ~ Post-state check 5 ~

    //     assertEq(realEstateTnft.ownerOf(fifthTokenId), ALICE);
    //     assertEq(basket.outCounter(), preOutCounter + 5);
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, sixthTokenId);

    //     // ~ Execute redeem ~

    //     vm.startPrank(ALICE);
    //     basket.redeemTNFT(basket.balanceOf(ALICE)); // should redeem sixthTokenId
    //     vm.stopPrank();

    //     // ~ Post-state check 6 ~

    //     assertEq(realEstateTnft.ownerOf(sixthTokenId), ALICE);
    //     assertEq(basket.outCounter(), preOutCounter + 6);
    //     redeemable = basket.calculateFifo();
    //     assertEq(redeemable.tokenId, 0);

    //     // ~ sanity check ~

    //     assertEq(realEstateTnft.balanceOf(ALICE), totalTokens);
    //     assertEq(realEstateTnft.balanceOf(address(basket)), 0);
    //     assertEq(basket.totalSupply(), 0);

    //     deposited = basket.getDepositedTnfts();
    //     assertEq(deposited.length, 0);
    // }

    /// @notice Verifies redeem math -> proposed by Daniel.
    function test_baskets_redeemTNFT_math() public {

        // ~ Conig ~

        // deal category owner USDC to deposit into rentManager
        uint256 aliceRentBal = 10 * USD;
        uint256 bobRentBal = 5 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, aliceRentBal + bobRentBal);

        // Mint Alice token worth $100
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000, // 100 GBP TODO: Switch to USD
            1,
            1,
            1,
            ALICE
        );
        uint256 aliceToken = tokenIds[0];

        // Mint Bob token worth $50
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            50_000, // 50 GBP TODO: Switch to USD
            1,
            1,
            2,
            BOB
        );
        uint256 bobToken = tokenIds[0];

        assertNotEq(aliceToken, bobToken);

        // ~ Pre-state check ~

        assertEq(realEstateTnft.balanceOf(ALICE), 1);
        assertEq(realEstateTnft.balanceOf(BOB), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(ALICE), 0);
        assertEq(basket.balanceOf(BOB), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        // ~ Alice executes a deposit ~
        vm.startPrank(ALICE);
        realEstateTnft.approve(address(basket), aliceToken);
        basket.depositTNFT(address(realEstateTnft), aliceToken);
        vm.stopPrank();

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for alice's tnft
        MUMBAI_USDC.approve(address(rentManager), aliceRentBal);
        rentManager.deposit(
            aliceToken,
            address(MUMBAI_USDC),
            aliceRentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // Bob executes a deposit
        vm.startPrank(BOB);
        realEstateTnft.approve(address(basket), bobToken);
        basket.depositTNFT(address(realEstateTnft), bobToken);
        vm.stopPrank();

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        
        // deposit rent for bob's tnft
        MUMBAI_USDC.approve(address(rentManager), bobRentBal);
        rentManager.deposit(
            bobToken,
            address(MUMBAI_USDC),
            bobRentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // skip to end of vesting

        // Sanity rent check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 5 * USD);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 15 * USD);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        (,uint256 tokenIdRedeemable,,) = basket.nextToRedeem();

        uint256 quoteOut = basket.getQuoteOut(address(realEstateTnft), tokenIdRedeemable);
        uint256 preBalAlice = basket.balanceOf(ALICE);

        // Bob executes a redeem of bobToken
        vm.startPrank(ALICE);
        basket.redeemTNFT(basket.balanceOf(ALICE));
        vm.stopPrank();

        _mockVrfCoordinatorResponse(
            basketVrfConsumer.outstandingRequest(address(basket)),
            100
        );

        // Post-state check
        assertEq(rentManager.claimableRentForToken(aliceToken), 0);
        assertEq(rentManager.claimableRentForToken(bobToken), 5 * USD);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 5 * USD);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 10 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        assertEq(realEstateTnft.balanceOf(ALICE), 1);
        assertEq(realEstateTnft.balanceOf(BOB), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(ALICE), preBalAlice - quoteOut);
        assertEq(basket.totalSupply(), basket.balanceOf(BOB) + basket.balanceOf(ALICE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, bobToken);
        assertEq(deposited[0].fingerprint, 2);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], bobToken);
    }


    // ~ checkPrecision ~

    /// @notice Verifies precision calculation of shares when depositing or redeeming
    function test_baskets_checkPrecision_noRent_fuzzing(uint256 _value) public {
        _value = bound(_value, 10, 100_000_000_000); // range (.01 -> 100M)

        // ~ Config ~

        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));

        // create and mint nft to actor
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            _value, // 100,000 GBP
            1,   // stock
            1,   // mintCount
            1,   // fingerprint
            JOE  // receiver
        );

        uint256 tokenId = tokenIds[0];

        // verify Joe received token
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        // sanity check
        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(),  0);

        // get usd value of token and quote for deposit
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 quote = basket.getQuoteIn(address(realEstateTnft), tokenId);
        uint256 feeTaken = _calculateFeeAmount(quote);
        uint256 amountAfterFee = _calculateAmountAfterFee(quote);

        assertEq(quote, usdValue);
        assertEq(quote, amountAfterFee + feeTaken);

        // ~ Joe deposits ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        // state check
        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            2
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));

        assertEq(basket.balanceOf(JOE), amountAfterFee);
        assertEq(basket.totalSupply(),  amountAfterFee);

        // ~ Joe redeems ~

        vm.startPrank(JOE);
        basket.redeemTNFT(basket.balanceOf(JOE));
        vm.stopPrank();

        // state check -> verify totalSup is 0. SharesRequired == total balance of actor
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(),  0);
    }

    /// @notice Verifies precision calculation of shares when depositing or redeeming
    function test_baskets_checkPrecision_rent_fuzzing(uint256 _value, uint256 _rent) public {
        _value = bound(_value, 10, 100_000_000_000); // range (.01 -> 100M) decimals = 3
        _rent  = bound(_rent, 1, 1_000_000_000_000); // range (.000001 -> 1M) decimals = 6

        // ~ Config ~

        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));

        // create and mint nft to actor
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            _value, // 100,000 GBP
            1,   // stock
            1,   // mintCount
            1,   // fingerprint
            JOE  // receiver
        );

        uint256 tokenId = tokenIds[0];

        // verify Joe received token
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        // deal rent to basket
        deal(address(MUMBAI_USDC), address(basket), _rent);

        // sanity check
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), _rent);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(),  0);

        // get usd value of token
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 quote = basket.getQuoteIn(address(realEstateTnft), tokenId);
        uint256 feeTaken = _calculateFeeAmount(quote);
        uint256 amountAfterFee = _calculateAmountAfterFee(quote);

        assertEq(quote, usdValue);
        assertEq(quote, amountAfterFee + feeTaken);

        // ~ Joe deposits ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        // state check
        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            2
        );

        assertEq(MUMBAI_USDC.balanceOf(address(basket)), _rent);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));

        assertEq(basket.balanceOf(JOE), amountAfterFee);
        assertEq(basket.totalSupply(),  amountAfterFee);

        uint256 quoteOut = basket.getQuoteOut(address(realEstateTnft), tokenId);
        uint256 preBasketBalJoe = basket.balanceOf(JOE);

        // ~ Joe redeems ~

        vm.startPrank(JOE);
        basket.redeemTNFT(basket.balanceOf(JOE));
        vm.stopPrank();

        // state check -> verify totalSup is 0. SharesRequired == total balance of actor
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        assertEq(MUMBAI_USDC.balanceOf(address(basket)), _rent);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        assertEq(basket.balanceOf(JOE), preBasketBalJoe - quoteOut);
        assertEq(basket.totalSupply(),  basket.balanceOf(JOE));
    }


    // ----------------------
    // View Method Unit Tests
    // ----------------------


    // ~ getTotalValueOfBasket ~
    // TODO: Write getTotalValueOfBasket test using fuzzing

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket
    function test_baskets_getTotalValueOfBasket_single() public {

        assertEq(basket.getTotalValueOfBasket(), 0);

        // deposit TNFT of certain value -> $650k usd
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // get nft value
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        assertEq(usdValue1, 650_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager
        uint256 amount = 10_000 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        MUMBAI_USDC.approve(address(rentManager), amount);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(MUMBAI_USDC),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get rent value
        uint256 rentClaimable = rentManager.claimableRentForToken(JOE_TOKEN_ID);
        assertEq(rentClaimable, 10_000 * USD); //1e6

        // grab rent value
        basket.rebase();

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), rentClaimable * 10**12);
        assertEq(totalValue, usdValue1 + basket.getRentBal());
    }

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket with many TNFTs.
    function test_baskets_getTotalValueOfBasket_multiple() public {

        assertEq(basket.getTotalValueOfBasket(), 0);

        // Joe deposits TNFT of certain value -> $650k usd
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Nik deposits TNFT of certain value -> $780k usd
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), NIK_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();

        // get nft value of tnft 1
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        assertEq(usdValue1, 650_000 ether); //1e18

        // get nft value of tnft 2
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);
        assertEq(usdValue2, 780_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager for tnft 1 and tnft 2
        uint256 amount1 = 10_000 * USD;
        uint256 amount2 = 14_000 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, amount1 + amount2);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for tnft 1
        MUMBAI_USDC.approve(address(rentManager), amount1);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(MUMBAI_USDC),
            amount1,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for tnft 2
        MUMBAI_USDC.approve(address(rentManager), amount2);
        rentManager.deposit(
            NIK_TOKEN_ID,
            address(MUMBAI_USDC),
            amount2,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get claimable rent value for tnft 1
        uint256 rentClaimable1 = rentManager.claimableRentForToken(JOE_TOKEN_ID);
        assertEq(rentClaimable1, amount1);

        // get claimable rent value for tnft 2
        uint256 rentClaimable2 = rentManager.claimableRentForToken(NIK_TOKEN_ID);
        assertEq(rentClaimable2, amount2);

        // grab rent value
        basket.rebase();

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), (rentClaimable1 * 10**12) + (rentClaimable2 * 10**12));
        assertEq(totalValue, usdValue1 + usdValue2 + basket.getRentBal());
    }


    // ~ notify ~

    /// @notice Verifies state changes when a successful call to Basket::notify is executed.
    function test_baskets_notify() public {

        // ~ config ~

        uint256 tokenId = JOE_TOKEN_ID;
        uint256 newNftValue = 625_000_000; //GBP -> 25% more expensive

        // get fingerprint
        uint256 fingerprint = realEstateTnft.tokensFingerprint(tokenId);

        // Joe deposits NFT
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        // ~ Pre-state check ~

        uint256 pre_usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 pre_sharePrice = basket.getSharePrice();
        uint256 pre_totalBasketVal = basket.getTotalValueOfBasket();

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(basket.totalNftValue(), pre_usdValue);
        assertEq(basket.valueTracker(address(realEstateTnft), tokenId), pre_usdValue);
        assertEq(basket.valueTracker(address(realEstateTnft), tokenId), pre_totalBasketVal);

        // ~ Update Token Price -> notify ~
        
        chainlinkRWAOracle.updateItem(fingerprint, newNftValue, 0);

        // ~ Execute a deposit ~

        uint256 post_usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 post_sharePrice = basket.getSharePrice();
        uint256 post_totalBasketVal = basket.getTotalValueOfBasket();

        assertGt(post_usdValue, pre_usdValue);
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(basket));

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertGt(post_sharePrice, pre_sharePrice);
        assertEq(basket.totalNftValue(), post_usdValue);
        assertEq(basket.valueTracker(address(realEstateTnft), tokenId), post_usdValue);

        // ~ logs ~

        console2.log("PRE USD VALUE", pre_usdValue);
        console2.log("POST USD VALUE", post_usdValue);

        console2.log("PRE SHARE PRICE", pre_sharePrice);
        console2.log("POST SHARE PRICE", post_sharePrice);

        console2.log("PRE TOTAL VALUE", pre_totalBasketVal);
        console2.log("POST TOTAL VALUE", post_totalBasketVal);
    }


    // ~ withdrawRent ~

    /// @notice Verifies proper state change upon a successful execution of Basket::withdrawRent.
    function test_baskets_withdrawRent() public {

        // ~ config ~

        // transfer USDC into basket
        // deposit a token or two into basket
        // deposit vested rent for tokens
        // withdraw all rent bal
        // invoke a revert

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // get nft value
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        assertEq(usdValue, 650_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager
        uint256 amount = 10_000 * USD;
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        MUMBAI_USDC.approve(address(rentManager), amount);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(MUMBAI_USDC),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // go to end of vesting period
        skip(1);

        // also deal USDC straight into the basket
        deal(address(MUMBAI_USDC), address(basket), amount);

        // ~ Pre-state check ~
        assertEq(basket.getRentBal(), (amount * 2) * 10**12);
        assertEq(basket.primaryRentToken().balanceOf(factoryOwner), 0);

        // ~ Execute withdrawRent ~

        // Force revert
        vm.prank(factoryOwner);
        vm.expectRevert("Amount exceeds withdrawable rent");
        basket.withdrawRent((amount * 2) + 1);

        vm.prank(factoryOwner);
        basket.withdrawRent(amount * 2);

        // ~ Pre-state check ~

        assertEq(basket.getRentBal(), 0);
        assertEq(basket.primaryRentToken().balanceOf(factoryOwner), amount * 2);
    }

    
    // ~ rebasing ~

    /// @notice Verifies proper state changes during rebase
    function test_baskets_rebase() public {

        // ~ Config ~

        uint256 amountRent = 10_000 * USD;

        // create token of certain value
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, //100k gbp
            1,
            1,
            1, // fingerprint
            ALICE
        );
        uint256 tokenId = tokenIds[0];

        // deposit into basket
        vm.startPrank(ALICE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        // deposit rent for that TNFT (no vesting)
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        MUMBAI_USDC.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(MUMBAI_USDC),
            amountRent,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // skip to end of vesting period
        skip(1);

        //uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);

        // ~ Sanity check ~

        uint256 rentClaimable = rentManager.claimableRentForToken(tokenId);
        assertEq(rentClaimable, amountRent);
        assertEq(basket.tokenDeposited(address(realEstateTnft), tokenId), true);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));

        // ~ Pre-state check ~

        uint256 increaseRatio = (amountRent * 10**12) * 1e18 / basket.getTotalValueOfBasket();
        emit log_named_uint("% increase post-rebase", increaseRatio); // 76923 == 7.6923%

        uint256 preTotalValue = basket.getTotalValueOfBasket();
        uint256 preTotalSupply = basket.totalSupply();

        assertEq(preTotalSupply, basket.balanceOf(ALICE));

        emit log_named_uint("total supply", basket.totalSupply());     // 129350000000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 130000000000000000000000

        // ~ rebase ~

        basket.rebase();

        // ~ Post-state check ~

        uint256 postRebaseSupply = preTotalSupply + ((preTotalSupply * (amountRent * 10**12)) / preTotalValue);

        assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
        assertGt(basket.totalSupply(), preTotalSupply);
        assertGt(basket.getTotalValueOfBasket(), preTotalValue);
        assertWithinDiff(
            basket.totalSupply(),
            postRebaseSupply,
            1e16
        ); // deviation of .01 or lower is accepted

        emit log_named_uint("total supply", basket.totalSupply());     // 139299999999999999990050
        emit log_named_uint("total supply prediction", postRebaseSupply);     // 139300000000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 140000000000000000000000

    }
}