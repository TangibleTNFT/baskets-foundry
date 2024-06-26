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
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

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
import { MockMatrixOracle } from "@tangible/tests/mocks/MockMatrixOracle.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { CurrencyCalculator } from "../src/CurrencyCalculator.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "../src/interfaces/IGetNotificationDispatcher.sol";
import { IUSTB } from "../src/interfaces/IUSTB.sol";

// local helper contracts
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title BasketsIntegrationTest
 * @author Chase Brown
 * @notice This test file contains integration tests for the baskets protocol. We import unreal addresses of the underlying layer
 *         of smart contracts via UnrealAddresses.sol.
 */
contract BasketsIntegrationTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public basket;
    BasketManager public basketManager;
    CurrencyCalculator public currencyCalculator;
    BasketsVrfConsumer public basketVrfConsumer;

    // tangible unreal contracts
    FactoryV2 public factoryV2 = FactoryV2(Unreal_FactoryV2);
    TangibleNFTV2 public realEstateTnft = TangibleNFTV2(Unreal_TangibleREstateTnft);
    RealtyOracleTangibleV2 public realEstateOracle = RealtyOracleTangibleV2(Unreal_RealtyOracleTangibleV2);
    MockMatrixOracle public chainlinkRWAOracle = MockMatrixOracle(Unreal_MockMatrix);
    TNFTMarketplaceV2 public marketplace = TNFTMarketplaceV2(Unreal_Marketplace);
    TangiblePriceManagerV2 public priceManager = TangiblePriceManagerV2(Unreal_PriceManager);
    CurrencyFeedV2 public currencyFeed = CurrencyFeedV2(Unreal_CurrencyFeedV2);
    TNFTMetadata public metadata = TNFTMetadata(Unreal_TNFTMetadata);
    RentManager public rentManager = RentManager(Unreal_RentManagerTnft);
    RWAPriceNotificationDispatcher public notificationDispatcher = RWAPriceNotificationDispatcher(Unreal_RWAPriceNotificationDispatcher);

    // ~ Actors and Variables ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public TANGIBLE_LABS; // NOTE: category owner

    address public rentManagerDepositor = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    uint256 internal portion;

    uint256 internal CREATOR_TOKEN_ID;
    uint256 internal JOE_TOKEN_ID;
    uint256 internal NIK_TOKEN_ID;

    ERC20Mock public DAI_MOCK;

    uint256[] internal preMintedTokens;

    /// @notice Config function for test cases.
    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        emit log_uint(block.chainid);

        factoryOwner = IOwnable(address(factoryV2)).owner();

        ERC20Mock dai = new ERC20Mock();
        DAI_MOCK = dai;

        // new category owner
        TANGIBLE_LABS = factoryV2.categoryOwner(ITangibleNFT(address(realEstateTnft)));

        // Deploy Basket implementation
        basket = new Basket();

        // Deploy CurrencyCalculator
        currencyCalculator = new CurrencyCalculator();

        // Deploy proxy for CurrencyCalculator -> initialize
        ERC1967Proxy currencyCalculatorProxy = new ERC1967Proxy(
            address(currencyCalculator),
            abi.encodeWithSelector(CurrencyCalculator.initialize.selector,
                address(factoryV2),
                100 * 365 days, // 100 year maxAge for testing
                100 * 365 days // 100 year maxAge for testing
            )
        );
        currencyCalculator = CurrencyCalculator(address(currencyCalculatorProxy));

        // Deploy BasketManager
        basketManager = new BasketManager();

        // Deploy proxy for basketManager -> initialize
        ERC1967Proxy basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(DAI_MOCK),
                false,
                address(currencyCalculator)
            )
        );
        basketManager = BasketManager(address(basketManagerProxy));

        // Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // Deploy proxy for basketsVrfConsumer -> initialize
        ERC1967Proxy vrfConsumerProxy = new ERC1967Proxy(
            address(basketVrfConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                address(factoryV2),
                block.chainid // must be testnet
            )
        );
        basketVrfConsumer = BasketsVrfConsumer(address(vrfConsumerProxy));

        // set Gelato Operator on basketsVrfConsumer
        vm.prank(factoryOwner);
        basketVrfConsumer.updateOperator(GELATO_OPERATOR);

        // set basketVrfConsumer address on basketManager
        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        // set revenueShare address on basketManager
        vm.prank(factoryOwner);
        basketManager.setRevenueDistributor(REV_SHARE); // RevenueDistributor

        // set rebase controller
        vm.prank(factoryOwner);
        basketManager.setRebaseController(REBASE_CONTROLLER);

        // updateDepositor for rent manager
        vm.prank(factoryV2.categoryOwner(ITangibleNFT(realEstateTnft)));
        rentManager.updateDepositor(TANGIBLE_LABS);

        // set basketManager
        vm.prank(factoryOwner);
        factoryV2.setContract(FactoryV2.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // set currencyFeed
        vm.prank(factoryOwner);
        factoryV2.setContract(FactoryV2.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        // whitelist basketManager on NotificationDispatcher
        vm.prank(TANGIBLE_LABS); // category owner
        notificationDispatcher.addWhitelister(address(basketManager));
        assertEq(notificationDispatcher.approvedWhitelisters(address(basketManager)), true);

        vm.startPrank(ORACLE_OWNER);
        // set tangibleWrapper to be real estate oracle on chainlink oracle.
        chainlinkRWAOracle.setTangibleWrapperAddress(
            address(realEstateOracle)
        );

        // create new item with fingerprint.
        // chainlinkRWAOracle.createItem(
        //     RE_FINGERPRINT_1,  // fingerprint
        //     200_000_000,     // weSellAt
        //     0,            // lockedAmount
        //     10,           // stock
        //     uint16(826),  // currency -> GBP ISO NUMERIC CODE
        //     uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        // );
        // chainlinkRWAOracle.createItem(
        //     RE_FINGERPRINT_2,  // fingerprint
        //     500_000_000,     // weSellAt
        //     0,            // lockedAmount
        //     10,           // stock
        //     uint16(826),  // currency -> GBP ISO NUMERIC CODE
        //     uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        // );
        // chainlinkRWAOracle.createItem(
        //     RE_FINGERPRINT_3,  // fingerprint
        //     600_000_000,     // weSellAt
        //     0,            // lockedAmount
        //     10,           // stock
        //     uint16(826),  // currency -> GBP ISO NUMERIC CODE
        //     uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        // );
        chainlinkRWAOracle.updateItem( // 1
            RE_FINGERPRINT_1,
            200_000_000,
            0
        );
        chainlinkRWAOracle.updateStock(
            RE_FINGERPRINT_1,
            10
        );
        chainlinkRWAOracle.updateItem( // 2
            RE_FINGERPRINT_2,
            500_000_000,
            0
        );
        chainlinkRWAOracle.updateStock(
            RE_FINGERPRINT_2,
            10
        );
        chainlinkRWAOracle.updateItem( // 3
            RE_FINGERPRINT_3,
            600_000_000,
            0
        );
        chainlinkRWAOracle.updateStock(
            RE_FINGERPRINT_3,
            10
        );
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
        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher1);
        CREATOR_TOKEN_ID = preMintedTokens[0]; // 1

        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher2);
        JOE_TOKEN_ID = preMintedTokens[0]; // 2

        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher3);
        NIK_TOKEN_ID = preMintedTokens[0]; // 3

        // transfer token to CREATOR
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, CREATOR, CREATOR_TOKEN_ID);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(CREATOR), 1);

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, JOE_TOKEN_ID);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(JOE), 1);

        // transfer token to NIK
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, NIK, NIK_TOKEN_ID);
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
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(CREATOR_TOKEN_ID)
        );
        vm.stopPrank();

        basket = Basket(address(_basket));

        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(basket.balanceOf(CREATOR), keccak256(abi.encodePacked(address(realEstateTnft), CREATOR_TOKEN_ID)));
        vm.stopPrank();

        // rebase controller sets the rebase manager.
        vm.prank(REBASE_CONTROLLER);
        basket.updateRebaseIndexManager(REBASE_INDEX_MANAGER);

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
        //emit log_named_address("address of priceFeed", address(priceFeed));

        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 exchangeRate = uint(price) + currencyFeed.conversionPremiums(currency);
        emit log_named_uint("Price of GBP/USD with premium", exchangeRate);

        // get decimal representation of exchange rate
        uint256 priceDecimals = priceFeed.decimals();
        //emit log_named_uint("price feed decimals", priceDecimals);
 
        // ~ get USD Value of property ~

        // calculate total USD value of property
        UsdValue = (exchangeRate * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
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

    /// @notice Helper function for creating items and minting to a designated address.
    function _createItemAndMint(address tnft, uint256 _sellAt, uint256 _stock, uint256 _mintCount, uint256 _fingerprint, address _receiver, uint16 _currency) internal returns (uint256[] memory) {
        require(_mintCount >= _stock, "mint count must be gt stock");

        vm.startPrank(ORACLE_OWNER);
        // create new item with fingerprint.
        chainlinkRWAOracle.createItem(
            _fingerprint, // fingerprint
            _sellAt,      // weSellAt
            0,            // lockedAmount
            _stock,       // stock
            _currency,    // custom currency
            _currency     // custom country
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

    /// @notice This helper method is used to execute a mock callback from the vrf coordinator.
    function _mockVrfCoordinatorResponse(address _basket, uint256 _randomWord) internal {
        uint256 requestId = Basket(_basket).pendingSeedRequestId();
        uint256 roundId = _round();

        bytes memory data = "";
        bytes memory dataWithRound = abi.encode(roundId, abi.encode(requestId, data));

        vm.prank(GELATO_OPERATOR);
        basketVrfConsumer.fulfillRandomness(_randomWord, dataWithRound);
    }

    /// @notice Emulates the computation on GelatoVRFConsumerBase when calculating round number of drand.
    function _round() internal view returns (uint256 round) {
        // solhint-disable-next-line not-rely-on-time
        uint256 elapsedFromGenesis = block.timestamp - 1692803367;
        uint256 currentRound = (elapsedFromGenesis / 3) + 1;

        round = block.chainid == 1 ? currentRound + 4 : currentRound + 1;
    }

    /// @notice Helper method for calling Basket::reinvestRent method.
    function reinvest(address _basket, address rentToken, uint256 amount, uint256 tokenId) external {
        // transfer tokens here
        IERC20(rentToken).transferFrom(_basket, address(this), amount);

        // deposit into basket
        realEstateTnft.approve(address(_basket), tokenId);
        Basket(_basket).depositTNFT(address(realEstateTnft), tokenId);
    }

    /// @notice Helper method for calling Basket::reinvestRent method.
    function reinvestNoDeposit(address _basket, address rentToken, uint256 amount) external {
        // transfer tokens here
        IERC20(rentToken).transferFrom(_basket, address(this), amount);
    }

    /// @notice Helper method to test edge case when CurrencyCalculator returns 0 when Basket::getUSDValue is called.
    function getUSDValue(address,uint256) external pure returns (uint256) {
        return 0;
    }


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
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
        assertEq(basketVrfConsumer.factory(), address(factoryV2));
        assertEq(basketVrfConsumer.operator(), GELATO_OPERATOR);

        // verify BasketManager initial state
        assertEq(basketManager.factory(), address(factoryV2));
        assertEq(basketManager.featureLimit(), 10);
        assertNotEq(address(basketManager.beacon()), address(0));
        assertNotEq(basketManager.beacon().implementation(), address(0));

        // verify basket
        assertEq(basket.currencySupported("GBP"), true);
        assertEq(basket.currencyDecimals("GBP"), 3);
        assertEq(basket.totalNftValueByCurrency("GBP"), 0);
        
        string[] memory supportedCurrencies = basket.getSupportedCurrencies();
        assertEq(supportedCurrencies.length, 1);
        assertEq(supportedCurrencies[0], "GBP");
    }


    // ----------
    // Unit Tests
    // ----------

    // ~ Initializers ~

    /// @notice Verifies restrictions when initializing a new Basket contract.
    function test_baskets_initializer_restrictions() public {
        Basket newBasket = new Basket();

        uint256[] memory features = new uint256[](2);
        features[0] = RE_FEATURE_2;
        features[1] = RE_FEATURE_1;

        vm.expectRevert(abi.encodeWithSelector(IBasket.ZeroAddress.selector));
        new ERC1967Proxy(
            address(newBasket),
            abi.encodeWithSelector(Basket.initialize.selector,
                "test basket",
                "t",
                address(0),
                RE_TNFTTYPE,
                address(UNREAL_DAI),
                false,
                features,
                UK_ISO,
                msg.sender
            )
        );
    }

    /// @notice Verifies restrictions and proper state when initializing a new BasketVrfConsumer contract.
    function test_baskets_basketsVrfConsumer_initializer() public {
        BasketsVrfConsumer newConsumer = new BasketsVrfConsumer();

        // cannot initialize a new BasketsVrfConsumer with factory address(0).
        vm.expectRevert(abi.encodeWithSelector(BasketsVrfConsumer.ZeroAddress.selector));
        ERC1967Proxy prox = new ERC1967Proxy(
            address(newConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                address(0),
                block.chainid
            )
        );

        // initialize new vrf consumer successfully
        prox = new ERC1967Proxy(
            address(newConsumer),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                address(factoryV2),
                block.chainid
            )
        );
        newConsumer = BasketsVrfConsumer(address(prox));

        // post-state check 
        assertEq(newConsumer.factory(), address(factoryV2));
        assertEq(newConsumer.testnetChainId(), block.chainid);
    }


    // ~ Deposit Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT is executed.
    function test_baskets_depositTNFT_single() public {

        // ~ Pre-state check ~

        assertEq(basket.getTotalValueOfBasket(), 0);

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 quote = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);

        // ~ Execute a deposit ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // restriction check -> Can't deposit token that's already deposited
        vm.expectRevert(abi.encodeWithSelector(IBasket.TokenAlreadyDeposited.selector, address(realEstateTnft), JOE_TOKEN_ID));
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", basket.getSharePrice());

        // ~ Post-state check ~

        assertWithinPrecision(
            (basket.balanceOf(JOE) * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            0
        );

        uint256 fingerprint = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(JOE_TOKEN_ID);
        (, uint256 nativeValue,) = currencyCalculator.getTnftNativeValue(address(realEstateTnft), fingerprint);
        assertEq(basket.totalNftValueByCurrency("GBP"), nativeValue);
        assertEq(basket.getTotalValueOfBasket(), usdValue);

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), quote);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);

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

    /// @notice Verifies the usage of a cap on amount of deposits can be made in a basket.
    function test_baskets_depositTNFT_cap() public {

        // ~ config ~

        vm.prank(factoryOwner);
        basket.updateCap(1);

        // ~ Execute a deposit ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // ~ Nik attempts a deposit -> fails ~

        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), NIK_TOKEN_ID);
        vm.expectRevert(abi.encodeWithSelector(IBasket.CapExceeded.selector));
        basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();
    }

    /// @notice Verifies the usage of a cap on amount of deposits can be made in a basket.
    function test_baskets_claimRentForToken() public {

        // ~ config ~

        // deposit token and rent
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        uint256 amountRent = 10 * 1e18;
        deal(address(DAI_MOCK), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        DAI_MOCK.approve(address(rentManager), amountRent);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(DAI_MOCK),
            amountRent,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();
        vm.warp(block.timestamp + 1);

        // ~ Pre-state check ~

        assertEq(DAI_MOCK.balanceOf(address(rentManager)), amountRent);
        assertEq(DAI_MOCK.balanceOf(address(basket)), 0);

        // ~ factory Owner executes claimRentForToken ~

        vm.prank(factoryOwner);
        basket.claimRentForToken(address(realEstateTnft), JOE_TOKEN_ID);

        // ~ Post-state check ~

        assertEq(DAI_MOCK.balanceOf(address(rentManager)), 0);
        assertEq(DAI_MOCK.balanceOf(address(basket)), amountRent);
    }

    /// @notice Verifies the various cases where a token is and is not compatible with a basket.
    function test_baskets_depositTNFT_initialDeposit() public {
        uint256[] memory _features = new uint256[](0);

        Basket newBasket = new Basket();
        ERC1967Proxy prox = new ERC1967Proxy(
            address(newBasket),
            abi.encodeWithSelector(Basket.initialize.selector,
                "test basket",
                "t",
                address(factoryV2),
                RE_TNFTTYPE,
                address(UNREAL_DAI),
                false,
                _features,
                0,
                JOE
            )
        );
        newBasket = Basket(address(prox));

        // restriction check -> Basket not whitelisted on NotificationDispatcher
        vm.startPrank(JOE);
        realEstateTnft.approve(address(newBasket), JOE_TOKEN_ID);
        vm.expectRevert(abi.encodeWithSelector(IBasket.NotWhitelisted.selector));
        newBasket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // whitelist basket
        vm.prank(TANGIBLE_LABS);
        notificationDispatcher.whitelistAddressAndReceiver(address(newBasket));
        
        // transfer Joe's token to BasketManager
        vm.prank(JOE);
        realEstateTnft.transferFrom(JOE, address(basketManager), JOE_TOKEN_ID);

        uint256 preBal = newBasket.balanceOf(JOE);

        // basket manager makes deposit -> Joe gets tokens (emulating initial deposit)
        vm.startPrank(address(basketManager));
        realEstateTnft.approve(address(newBasket), JOE_TOKEN_ID);
        newBasket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        assertGt(newBasket.balanceOf(JOE), preBal);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT is executed.
    function test_baskets_depositTNFT_multiple() public {

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
        assertEq(basket.totalNftValueByCurrency("GBP"), 0);
        assertEq(basket.getTotalValueOfBasket(), 0);

        uint256 fingerprint1 = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(JOE_TOKEN_ID);
        uint256 fingerprint2 = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(NIK_TOKEN_ID);

        (, uint256 nativeValue1,) = currencyCalculator.getTnftNativeValue(address(realEstateTnft), fingerprint1);
        (, uint256 nativeValue2,) = currencyCalculator.getTnftNativeValue(address(realEstateTnft), fingerprint2);

        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        uint256 quote_Joe = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);

        // ~ Joe deposits TNFT ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // ~ Nik deposits TNFT ~

        uint256 quote_Nik = basket.getQuoteIn(address(realEstateTnft), NIK_TOKEN_ID);

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

        assertEq(basket.balanceOf(JOE), quote_Joe);
        assertEq(basket.balanceOf(NIK), quote_Nik);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);
        assertEq(basket.totalNftValueByCurrency("GBP"), nativeValue1 + nativeValue2);
        assertEq(basket.getTotalValueOfBasket(), usdValue1 + usdValue2);

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

    /// @notice Verifies proper amounts when Basket::getBatchQuoteIn is executed.
    function test_baskets_getBatchQuoteIn() public {
        address[] memory _tangibleNFTs = new address[](2);
        _tangibleNFTs[0] = address(realEstateTnft);
        _tangibleNFTs[1] = address(realEstateTnft);

        uint256[] memory _tokenIds = new uint256[](2);
        _tokenIds[0] = JOE_TOKEN_ID;
        _tokenIds[1] = NIK_TOKEN_ID;

        uint256 quote_Joe = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 quote_Nik = basket.getQuoteIn(address(realEstateTnft), NIK_TOKEN_ID);

        uint256[] memory shares = basket.getBatchQuoteIn(_tangibleNFTs, _tokenIds);

        assertEq(shares[0], quote_Joe);
        assertEq(shares[1], quote_Nik);
    }

    /// @notice Verifies the various cases where a token is and is not compatible with a basket.
    function test_baskets_isCompatibleTnft() public {
        // gold bars TNFT not compatible with RE basket (tnftType does not match)
        assertEq(basket.isCompatibleTnft(Unreal_TangibleGoldBarsTnft, 1), false);
        // RE type is compatible with basket, types match
        assertEq(basket.isCompatibleTnft(address(realEstateTnft), 1), true);

        // Create new basket with RE type, RE feature, and UK location
        Basket newBasket = new Basket();
        ERC1967Proxy prox = new ERC1967Proxy(
            address(newBasket),
            abi.encodeWithSelector(Basket.initialize.selector,
                "test basket",
                "t",
                address(factoryV2),
                RE_TNFTTYPE,
                address(UNREAL_DAI),
                false,
                _asSingletonArrayUint(RE_FEATURE_1),
                UK_ISO,
                msg.sender
            )
        );
        newBasket = Basket(address(prox));

        // create token in UK without RE feature
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000,
            1,
            1,
            9999,
            BOB,
            UK_ISO // XAU
        );
        uint256 UKTokenId = tokenIds[0];
        // create token in US without RE feature
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000,
            1,
            1,
            9998,
            BOB,
            US_ISO // US
        );
        uint256 USTokenId = tokenIds[0];

        // UK token is not compatible -> missing feature
        assertEq(newBasket.isCompatibleTnft(address(realEstateTnft), UKTokenId), false);
        // US token is not compatible -> missing feature
        assertEq(newBasket.isCompatibleTnft(address(realEstateTnft), USTokenId), false);

        // add RE feature to both tokens
        _addFeatureToCategory(address(realEstateTnft), UKTokenId, _asSingletonArrayUint(RE_FEATURE_1));
        _addFeatureToCategory(address(realEstateTnft), USTokenId, _asSingletonArrayUint(RE_FEATURE_1));

        // UK Token is now compatible - same type, feature, and location
        assertEq(newBasket.isCompatibleTnft(address(realEstateTnft), UKTokenId), true);
        // US Token is NOT compatible - same type, feature, but different location
        assertEq(newBasket.isCompatibleTnft(address(realEstateTnft), USTokenId), false);
    }

    /// @notice Verifies revert when currencyCalculator.getUSDValue returns 0 when Basket::getUSDValue is called.
    function test_baskets_getUSDValue_0() public {
        vm.prank(factoryOwner);
        basketManager.setCurrencyCalculator(address(this));

        vm.expectRevert(abi.encodeWithSelector(IBasket.UnsupportedTNFT.selector, address(realEstateTnft), JOE_TOKEN_ID));
        basket.getUSDValue(address(realEstateTnft), JOE_TOKEN_ID);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT is executed.
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
            UK_ISO,
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
        vm.expectRevert();
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

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT is executed.
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
            UK_ISO,
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
        vm.expectRevert();
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 1.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        // add feature 1 to TNFT
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_1));

        // Try to execute a deposit
        vm.startPrank(JOE);
        vm.expectRevert();
        _basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Post-state check 2.
        assertEq(_basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        // add feature 2 to TNFT
        _addFeatureToCategory(address(realEstateTnft), JOE_TOKEN_ID, _asSingletonArrayUint(RE_FEATURE_2));

        // Try to execute a deposit
        vm.startPrank(JOE);
        vm.expectRevert();
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

    /// @notice Verifies restrictions and correct state changes when Basket::batchDepositTNFT is executed.
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

        vm.expectRevert();
        basket.batchDepositTNFT(tnfts, tokenIds);
    }

    function test_baskets_depositTNFT_diffCurrencies() public {

        // ~ Config ~

        // create token of XAU currency
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // XAU is 3 decimals
            1,
            1,
            9999, // fp
            BOB,
            959 // XAU
        );
        uint256 tokenIdXAU = tokenIds[0];

        // create token of USD currency
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // USD is 3 decimals
            1,
            1,
            9998, // fp
            BOB,
            840 // USD
        );
        uint256 tokenIdUSD = tokenIds[0];

        (, uint256 nativeValueXAU,) = currencyCalculator.getTnftNativeValue(
            address(realEstateTnft),
            ITangibleNFT(address(realEstateTnft)).tokensFingerprint(tokenIdXAU)
        );
        uint256 usdValueXAU = currencyCalculator.getUSDValue(address(realEstateTnft), tokenIdXAU);
        emit log_named_uint("usd val xau token", usdValueXAU);

        (, uint256 nativeValueUSD,) = currencyCalculator.getTnftNativeValue(
            address(realEstateTnft),
            ITangibleNFT(address(realEstateTnft)).tokensFingerprint(tokenIdUSD)
        );
        uint256 usdValueUSD = currencyCalculator.getUSDValue(address(realEstateTnft), tokenIdUSD);
        emit log_named_uint("usd val usd token", usdValueUSD);


        // ~ Pre-state check ~

        assertEq(realEstateTnft.balanceOf(BOB), 2);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.getTotalValueOfBasket(), 0);

        assertEq(basket.currencySupported("GBP"), true);
        assertEq(basket.currencyDecimals("GBP"), 3);
        assertEq(basket.totalNftValueByCurrency("GBP"), 0);

        assertEq(basket.currencySupported("XAU"), false);
        assertEq(basket.currencyDecimals("XAU"), 0);
        assertEq(basket.totalNftValueByCurrency("XAU"), 0);

        assertEq(basket.currencySupported("USD"), false);
        assertEq(basket.currencyDecimals("USD"), 0);
        assertEq(basket.totalNftValueByCurrency("USD"), 0);
        
        string[] memory supportedCurrencies = basket.getSupportedCurrencies();
        assertEq(supportedCurrencies.length, 1);
        assertEq(supportedCurrencies[0], "GBP");

        // ~ Deposit XAU Token ~

        vm.startPrank(BOB);
        realEstateTnft.approve(address(basket), tokenIdXAU);
        basket.depositTNFT(address(realEstateTnft), tokenIdXAU);
        vm.stopPrank();

        // ~ Post-state check 1 ~

        assertEq(realEstateTnft.balanceOf(BOB), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.getTotalValueOfBasket(), usdValueXAU);

        assertEq(basket.currencySupported("GBP"), true);
        assertEq(basket.currencyDecimals("GBP"), 3);
        assertEq(basket.totalNftValueByCurrency("GBP"), 0);

        assertEq(basket.currencySupported("XAU"), true);
        assertEq(basket.currencyDecimals("XAU"), 3);
        assertEq(basket.totalNftValueByCurrency("XAU"), nativeValueXAU);

        assertEq(basket.currencySupported("USD"), false);
        assertEq(basket.currencyDecimals("USD"), 0);
        assertEq(basket.totalNftValueByCurrency("USD"), 0);
        
        supportedCurrencies = basket.getSupportedCurrencies();
        assertEq(supportedCurrencies.length, 2);
        assertEq(supportedCurrencies[0], "GBP");
        assertEq(supportedCurrencies[1], "XAU");

        // ~ Deposit USD Token ~

        vm.startPrank(BOB);
        realEstateTnft.approve(address(basket), tokenIdUSD);
        basket.depositTNFT(address(realEstateTnft), tokenIdUSD);
        vm.stopPrank();

        // ~ Post-state check 2 ~

        assertEq(realEstateTnft.balanceOf(BOB), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 2);

        assertEq(basket.getTotalValueOfBasket(), usdValueXAU + usdValueUSD);

        assertEq(basket.currencySupported("GBP"), true);
        assertEq(basket.currencyDecimals("GBP"), 3);
        assertEq(basket.totalNftValueByCurrency("GBP"), 0);

        assertEq(basket.currencySupported("XAU"), true);
        assertEq(basket.currencyDecimals("XAU"), 3);
        assertEq(basket.totalNftValueByCurrency("XAU"), nativeValueXAU);

        assertEq(basket.currencySupported("USD"), true);
        assertEq(basket.currencyDecimals("USD"), 3);
        assertEq(basket.totalNftValueByCurrency("USD"), nativeValueUSD);
        
        supportedCurrencies = basket.getSupportedCurrencies();
        assertEq(supportedCurrencies.length, 3);
        assertEq(supportedCurrencies[0], "GBP");
        assertEq(supportedCurrencies[1], "XAU");
        assertEq(supportedCurrencies[2], "USD");
    }


    // ~ Redeem Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT is executed.
    function test_baskets_redeemTNFT_single() public {

        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);

        uint256 quote = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);

        uint256 fingerprint = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(JOE_TOKEN_ID);
        (, uint256 nativeValue,) = currencyCalculator.getTnftNativeValue(address(realEstateTnft), fingerprint);
        uint256 usdValue = currencyCalculator.getUSDValue(address(realEstateTnft), JOE_TOKEN_ID);

        // ~ Config ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        bytes32 token = keccak256(abi.encodePacked(address(realEstateTnft), JOE_TOKEN_ID));

        // ~ Pre-state check ~

        //uint256 feeTaken = _calculateFeeAmount(quote);

        assertNotEq(basket.getTotalValueOfBasket(), 0);
        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(basket.totalNftValueByCurrency("GBP"), nativeValue);
        assertEq(basket.getTotalValueOfBasket(), usdValue);

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), quote);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);

        string[] memory supportedCurrencies = basket.getSupportedCurrencies();
        assertEq(supportedCurrencies.length, 1);

        // ~ State changes ~

        // Joe performs a redeem with 0 budget -> revert
        vm.prank(JOE);
        vm.expectRevert();
        basket.redeemTNFT(0, token);

        // Joe performs a redeem with over balance -> revert
        vm.prank(JOE);
        vm.expectRevert();
        basket.redeemTNFT(quote + 1, token);

        // Joe performs a redeem with 0 budget -> revert
        vm.prank(JOE);
        vm.expectRevert();
        basket.redeemTNFT(quote, keccak256(abi.encodePacked(address(realEstateTnft), JOE_TOKEN_ID + 1)));

        // Joe performs a redeem -> success
        vm.prank(JOE);
        basket.redeemTNFT(quote, token);

        // ~ Post-state check ~

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(basket.totalNftValueByCurrency("GBP"), 0);
        assertEq(basket.getTotalValueOfBasket(), 0);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);

        supportedCurrencies = basket.getSupportedCurrencies();
        assertEq(supportedCurrencies.length, 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT is executed for multiple TNFTs.
    function test_baskets_redeemTNFT_multiple() public {

        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preBalNik = realEstateTnft.balanceOf(NIK);

        uint256 fingerprint1 = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(JOE_TOKEN_ID);
        uint256 fingerprint2 = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(NIK_TOKEN_ID);

        (, uint256 nativeValue1,) = currencyCalculator.getTnftNativeValue(address(realEstateTnft), fingerprint1);
        (, uint256 nativeValue2,) = currencyCalculator.getTnftNativeValue(address(realEstateTnft), fingerprint2);

        uint256 usdValue1 = currencyCalculator.getUSDValue(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 usdValue2 = currencyCalculator.getUSDValue(address(realEstateTnft), NIK_TOKEN_ID);

        // ~ Config ~

        // Joe deposits token

        uint256 quote_Joe = basket.getQuoteIn(address(realEstateTnft), JOE_TOKEN_ID);

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Nik deposits token

        uint256 quote_Nik = basket.getQuoteIn(address(realEstateTnft), NIK_TOKEN_ID);

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

        assertEq(basket.totalNftValueByCurrency("GBP"), nativeValue1 + nativeValue2);
        assertEq(basket.getTotalValueOfBasket(), usdValue1 + usdValue2);

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe - 1);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 2);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(basket));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(basket));

        assertEq(basket.balanceOf(JOE), quote_Joe);
        assertEq(basket.balanceOf(NIK), quote_Nik);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);

        assertEq(basket.indexInDepositedTnfts(address(realEstateTnft), JOE_TOKEN_ID), 0);
        assertEq(basket.indexInDepositedTnfts(address(realEstateTnft), NIK_TOKEN_ID), 1);

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
        basket.redeemTNFT(basket.balanceOf(JOE), keccak256(abi.encodePacked(address(realEstateTnft), JOE_TOKEN_ID)));
        vm.stopPrank();

        // restriction check -> can't redeem when a seed request is in progress
        vm.startPrank(JOE);
        vm.expectRevert(abi.encodeWithSelector(IBasket.SeedRequestPending.selector));
        basket.redeemTNFT(1 ether, keccak256(abi.encodePacked(address(realEstateTnft), JOE_TOKEN_ID)));
        vm.stopPrank();

        // This redeem generates a request to vrf. Mock response.
        _mockVrfCoordinatorResponse(
            address(basket),
            100
        );

        // ~ Post-state check 1 ~

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(basket.totalNftValueByCurrency("GBP"), nativeValue2);
        assertEq(basket.getTotalValueOfBasket(), usdValue2);

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), JOE_TOKEN_ID), address(0));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), NIK_TOKEN_ID), address(basket));

        assertGt(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), quote_Nik);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);

        assertEq(basket.indexInDepositedTnfts(address(realEstateTnft), JOE_TOKEN_ID), 0);
        assertEq(basket.indexInDepositedTnfts(address(realEstateTnft), NIK_TOKEN_ID), 0);

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
        assertGt(basket.balanceOf(NIK), quote_Nik);

        // ~ Nik performs a redeem ~

        emit log_string("REDEEM 2");

        vm.startPrank(NIK);
        basket.redeemTNFT(basket.balanceOf(NIK), keccak256(abi.encodePacked(address(realEstateTnft), NIK_TOKEN_ID)));
        vm.stopPrank();

        // ~ Post-state check 2 ~

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1 ether,
            basket.getTotalValueOfBasket(),
            8
        );

        assertEq(basket.totalNftValueByCurrency("GBP"), 0);
        assertEq(basket.getTotalValueOfBasket(), 0);

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

        assertEq(basket.indexInDepositedTnfts(address(realEstateTnft), JOE_TOKEN_ID), 0);
        assertEq(basket.indexInDepositedTnfts(address(realEstateTnft), NIK_TOKEN_ID), 0);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    /// @notice Verifies redeem math -> proposed by Daniel.
    function test_baskets_redeemTNFT_math() public {

        // ~ Conig ~

        // deal category owner USDC to deposit into rentManager
        uint256 aliceRentBal = 10 * WAD;
        uint256 bobRentBal = 5 * WAD;
        deal(address(DAI_MOCK), TANGIBLE_LABS, aliceRentBal + bobRentBal);

        // Mint Alice token worth $100
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000, // 100 GBP
            1,
            1,
            1,
            ALICE
        );
        uint256 aliceToken = tokenIds[0];

        // Mint Bob token worth $50
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            50_000, // 50 GBP
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
        DAI_MOCK.approve(address(rentManager), aliceRentBal);
        rentManager.deposit(
            aliceToken,
            address(DAI_MOCK),
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
        DAI_MOCK.approve(address(rentManager), bobRentBal);
        rentManager.deposit(
            bobToken,
            address(DAI_MOCK),
            bobRentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // skip to end of vesting

        // Sanity rent check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * WAD);
        assertEq(rentManager.claimableRentForToken(bobToken), 5 * WAD);

        assertEq(DAI_MOCK.balanceOf(address(rentManager)), 15 * WAD);
        assertEq(DAI_MOCK.balanceOf(address(basket)), 0);
        assertEq(DAI_MOCK.balanceOf(ALICE), 0);
        assertEq(DAI_MOCK.balanceOf(BOB), 0);

        (,uint256 tokenIdRedeemable) = basket.nextToRedeem();

        uint256 quoteOut = basket.getQuoteOut(address(realEstateTnft), tokenIdRedeemable);
        uint256 preBalAlice = basket.balanceOf(ALICE);

        // Bob executes a redeem of bobToken
        vm.startPrank(ALICE);
        basket.redeemTNFT(basket.balanceOf(ALICE), keccak256(abi.encodePacked(address(realEstateTnft), aliceToken)));
        vm.stopPrank();

        _mockVrfCoordinatorResponse(
            address(basket),
            100
        );

        // Post-state check
        assertEq(rentManager.claimableRentForToken(aliceToken), 0);
        assertEq(rentManager.claimableRentForToken(bobToken), 5 * WAD);

        assertEq(DAI_MOCK.balanceOf(address(rentManager)), 5 * WAD);
        assertEq(DAI_MOCK.balanceOf(address(basket)), 10 * WAD);
        assertEq(DAI_MOCK.balanceOf(ALICE), 0);
        assertEq(DAI_MOCK.balanceOf(BOB), 0);

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
        //uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 quote = basket.getQuoteIn(address(realEstateTnft), tokenId);
        //uint256 feeTaken = _calculateFeeAmount(quote);

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

        assertEq(basket.balanceOf(JOE), quote);
        assertEq(basket.totalSupply(),  quote);

        // ~ Joe redeems ~

        vm.startPrank(JOE);
        basket.redeemTNFT(basket.balanceOf(JOE), keccak256(abi.encodePacked(address(realEstateTnft), tokenId)));
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
        deal(address(DAI_MOCK), address(basket), _rent);

        // sanity check
        assertEq(DAI_MOCK.balanceOf(address(basket)), _rent);
        assertEq(DAI_MOCK.balanceOf(JOE), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(),  0);

        // get usd value of token
        //uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 quote = basket.getQuoteIn(address(realEstateTnft), tokenId);
        //uint256 feeTaken = _calculateFeeAmount(quote);

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

        assertEq(DAI_MOCK.balanceOf(address(basket)), _rent);
        assertEq(DAI_MOCK.balanceOf(JOE), 0);

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));

        assertEq(basket.balanceOf(JOE), quote);
        assertEq(basket.totalSupply(),  quote);

        uint256 quoteOut = basket.getQuoteOut(address(realEstateTnft), tokenId);
        uint256 preBasketBalJoe = basket.balanceOf(JOE);

        // ~ Joe redeems ~

        vm.startPrank(JOE);
        basket.redeemTNFT(basket.balanceOf(JOE), keccak256(abi.encodePacked(address(realEstateTnft), tokenId)));
        vm.stopPrank();

        // state check -> verify totalSup is 0. SharesRequired == total balance of actor
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        assertEq(DAI_MOCK.balanceOf(address(basket)), _rent);
        assertEq(DAI_MOCK.balanceOf(JOE), 0);

        assertEq(basket.balanceOf(JOE), preBasketBalJoe - quoteOut);
        assertEq(basket.totalSupply(),  basket.balanceOf(JOE));
    }


    // ----------------------
    // View Method Unit Tests
    // ----------------------

    // ~ getTotalValueOfBasket ~
    
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
        assertEq(usdValue1, 655_000 ether);

        emit log_uint(DAI_MOCK.balanceOf(TANGIBLE_LABS));

        // deal category owner USTB to deposit into rentManager
        uint256 amount = 10_000 * WAD;
        deal(address(DAI_MOCK), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        DAI_MOCK.approve(address(rentManager), amount);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(DAI_MOCK),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get rent value
        uint256 rentClaimable = rentManager.claimableRentForToken(JOE_TOKEN_ID);
        assertEq(rentClaimable, 10_000 * WAD);

        // bob tries to rebase -> revert
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IBasket.NotAuthorized.selector, BOB));
        basket.rebase();

        // grab rent value
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        emit log_uint(basket.getRentBal());

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), rentClaimable - ((rentClaimable * basket.rentFee()) / 100_00));
        assertEq(totalValue, usdValue1 + (basket.getRentBal() * basket.decimalsDiff()));
        assertEq(basket.getRentBal(), basket.totalRentValue());
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
        assertEq(usdValue1, 655_000 ether); //1e18

        // get nft value of tnft 2
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);
        assertEq(usdValue2, 786_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager for tnft 1 and tnft 2
        uint256 amount1 = 10_000 * WAD;
        uint256 amount2 = 14_000 * WAD;
        deal(address(DAI_MOCK), TANGIBLE_LABS, amount1 + amount2);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for tnft 1
        DAI_MOCK.approve(address(rentManager), amount1);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(DAI_MOCK),
            amount1,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for tnft 2
        DAI_MOCK.approve(address(rentManager), amount2);
        rentManager.deposit(
            NIK_TOKEN_ID,
            address(DAI_MOCK),
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

        uint256 totalRent = rentClaimable1 + rentClaimable2;

        // grab rent value
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), totalRent - ((totalRent * basket.rentFee()) / 100_00));
        assertEq(totalValue, usdValue1 + usdValue2 + (basket.getRentBal() * basket.decimalsDiff()));
        assertEq(basket.getRentBal(), basket.totalRentValue());
    }


    // ~ notify ~

    /// @notice Verifies state changes when a successful call to Basket::notify is executed.
    function test_baskets_notify() public {

        // ~ config ~

        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            500_000_000,
            1,
            1,
            9999, // fp
            JOE
        );

        uint256 tokenId = tokenIds[0];
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

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1e18,
            basket.getTotalValueOfBasket(),
            8
        );
        assertEq(basket.totalNftValueByCurrency("GBP"), 500_000_000);
        assertEq(basket.getTotalValueOfBasket(), pre_usdValue);

        // ~ Update Token Price -> notify ~
        
        vm.prank(chainlinkRWAOracle.owner());
        chainlinkRWAOracle.updateItem(fingerprint, newNftValue, 0);

        // ~ Post-state check ~

        uint256 post_usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 post_sharePrice = basket.getSharePrice();

        assertGt(post_usdValue, pre_usdValue);
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(basket));

        assertWithinPrecision(
            (basket.totalSupply() * basket.getSharePrice()) / 1e18,
            basket.getTotalValueOfBasket(),
            8
        );
        assertGt(post_sharePrice, pre_sharePrice);
        assertEq(basket.totalNftValueByCurrency("GBP"), newNftValue);
        assertEq(basket.getTotalValueOfBasket(), post_usdValue);

        // ~ logs ~

        console2.log("PRE USD VALUE", pre_usdValue);
        console2.log("POST USD VALUE", post_usdValue);

        console2.log("PRE SHARE PRICE", pre_sharePrice);
        console2.log("POST SHARE PRICE", post_sharePrice);
    }

    /// @notice Verifies restrictions when calling Basket::notify()
    function test_baskets_notify_restrictions() public {
        // only notification dispatcher can call notify()
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IBasket.NotAuthorized.selector, BOB));
        basket.notify(address(realEstateTnft), 1, 0, 100_000, 200_000, 826);
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
        assertEq(usdValue, 655_000 ether); //1e18

        // deal category owner USDC to deposit into rentManager
        uint256 amount = 10_000 * WAD;
        uint256 fullRentAmount = amount * 2;

        deal(address(DAI_MOCK), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        DAI_MOCK.approve(address(rentManager), amount);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(DAI_MOCK),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // go to end of vesting period
        skip(1);

        // also deal USDC straight into the basket
        deal(address(DAI_MOCK), address(basket), amount);

        // ~ Sanity check ~

        assertEq(basket.getRentBal(), amount * 2);
        assertEq(basket.primaryRentToken().balanceOf(factoryOwner), 0);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), 0);

        uint256 revSharePortion = (fullRentAmount * basket.rentFee()) / 100_00;
        uint256 withdrawable = fullRentAmount - revSharePortion;

        // ~ Rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // ~ Pre-state check ~

        assertEq(basket.getRentBal(), withdrawable);
        assertEq(basket.totalRentValue(), withdrawable);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), revSharePortion);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + basket.totalRentValue(), fullRentAmount);

        // ~ Execute withdrawRent ~

        // estriction check -> Cannot withdraw more than withdrawable
        vm.prank(factoryOwner);
        vm.expectRevert();
        basket.withdrawRent((withdrawable) + 1);

        // restriction check -> Bob cannot call withdrawRent
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IBasket.NotAuthorized.selector, BOB));
        basket.withdrawRent(withdrawable);

        vm.prank(factoryOwner);
        basket.withdrawRent(withdrawable);

        // ~ Post-state check ~

        assertEq(basket.getRentBal(), 0);
        assertEq(basket.primaryRentToken().balanceOf(factoryOwner), withdrawable);
    }

    
    // ~ rebasing ~

    /// @notice Verifies proper state changes during rebase
    function test_baskets_rebase() public {

        // ~ Config ~

        uint256 amountRent = 10_000 * WAD;

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
        deal(address(DAI_MOCK), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        DAI_MOCK.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(DAI_MOCK),
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
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), 0);

        // ~ Pre-state check ~

        uint256 increaseRatio = (amountRent * 1e18) / basket.getTotalValueOfBasket();
        emit log_named_uint("% increase post-rebase", increaseRatio); // 76923 == 7.6923%

        uint256 preTotalValue = basket.getTotalValueOfBasket();
        uint256 preTotalSupply = basket.totalSupply();

        assertEq(preTotalSupply, basket.balanceOf(ALICE));

        emit log_named_uint("total supply", basket.totalSupply());     // 129350000000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 130000000000000000000000

        // ~ rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // ~ Post-state check ~

        uint256 postRebaseSupply = preTotalSupply + ((preTotalSupply * (amountRent - ((amountRent * basket.rentFee()) / 100_00))) / preTotalValue);

        assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
        assertGt(basket.totalSupply(), preTotalSupply);
        assertGt(basket.getTotalValueOfBasket(), preTotalValue);
        assertWithinDiff(
            basket.totalSupply(),
            postRebaseSupply,
            1e16
        ); // deviation of .01 or lower is acceptable
        assertEq(basket.getRentBal(), basket.totalRentValue());
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRent * basket.rentFee()) / 100_00);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + basket.totalRentValue(), amountRent);
 
        emit log_named_uint("decimals diff", basket.decimalsDiff());
        emit log_named_uint("total supply", basket.totalSupply());     // 139299999999999999990050
        emit log_named_uint("total supply prediction", postRebaseSupply);     // 139300000000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 140000000000000000000000
    }

    /// @notice Verifies proper state changes when Basket::updateRebaseIndexManager is called.
    function test_baskets_updateRebaseIndexManager() public {

        // ~ Pre-state check ~

        assertNotEq(basket.rebaseIndexManager(), address(222));

        // ~ Execute updateRebaseIndexManager with FactoryOwner ~

        vm.prank(factoryOwner);
        basket.updateRebaseIndexManager(address(222));

        // ~ Post-state check 1 ~

        assertEq(basket.rebaseIndexManager(), address(222));

        // ~ Execute updateRebaseIndexManager with RebaseController ~

        vm.prank(basketManager.rebaseController());
        basket.updateRebaseIndexManager(address(333));

        // ~ Post-state check 2 ~

        assertEq(basket.rebaseIndexManager(), address(333));
    }

    /// @notice Verifies restrictions for Basket::updateRebaseIndexManager() method.
    function test_baskets_updateRebaseIndexManager_restrictions() public {
        // random actor cannot call method
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IBasket.NotAuthorized.selector, BOB));
        basket.updateRebaseIndexManager(address(222));
    }

    /// @notice Verifies correct state changes when disableRebase is executed.
    function test_baskets_disableRebase() public {

        // ~ Config ~

        vm.prank(factoryOwner);
        basket.updateRebaseIndexManager(address(222));

        // ~ Pre-state check

        assertEq(basket.isRebaseDisabled(JOE), false);

        // ~ Execute disableRebase for Joe ~

        vm.prank(address(222));
        basket.disableRebase(JOE, true);

        // ~ Post-state check

        assertEq(basket.isRebaseDisabled(JOE), true);
    }

    /// @notice Verifies correct restrictions when disableRebase is executed.
    function test_baskets_disableRebase_restrictions() public {
        // Verify permissions
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IBasket.NotAuthorized.selector, BOB));
        basket.disableRebase(JOE, true);
    }

    /// @notice Verifies the overall value of the basket can decrease and as long as rent has increased, rebase is positive.
    function test_baskets_decreaseValue_thenRebase() public {

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

        // get nft value of tnft 2
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);

        // deal category owner USDC to deposit into rentManager for tnft 1 and tnft 2
        uint256 amount = 10_000 * WAD;
        deal(address(DAI_MOCK), TANGIBLE_LABS, amount);
        
        vm.prank(TANGIBLE_LABS);
        DAI_MOCK.transfer(address(basket), amount);

        // grab rent value
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // post state check 1
        uint256 totalValue = basket.getTotalValueOfBasket();
        emit log_named_uint("Total value of basket 1", totalValue);
        assertEq(totalValue, usdValue1 + usdValue2 + (basket.getRentBal() * basket.decimalsDiff()));
        assertEq(basket.getRentBal(), basket.totalRentValue());

        // Joe redeems NFT
        vm.startPrank(JOE);
        basket.redeemTNFT(
            basket.getQuoteOut(address(realEstateTnft), JOE_TOKEN_ID), 
            keccak256(abi.encodePacked(address(realEstateTnft), JOE_TOKEN_ID))
        );
        vm.stopPrank();

        // post state check 2
        totalValue = basket.getTotalValueOfBasket();
        emit log_named_uint("Total value of basket 2", totalValue);
        assertEq(totalValue, usdValue2 + (basket.getRentBal() * basket.decimalsDiff()));

        uint256 preRebaseIndex = basket.rebaseIndex();

        // try to rebase
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();
        assertEq(basket.rebaseIndex(), preRebaseIndex); // rebaseIndex does not change

        // deposit a bit more rent
        amount = 10 ether;
        deal(address(DAI_MOCK), TANGIBLE_LABS, amount);
        vm.prank(TANGIBLE_LABS);
        DAI_MOCK.transfer(address(basket), amount);

        // rebase
        preRebaseIndex = basket.rebaseIndex();

        // rebase
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();
        assertGt(basket.rebaseIndex(), preRebaseIndex); // rebaseIndex should be larger
    }


    // ~ sendRequestForSeed ~

    /// @notice This method verifies correct state changes when sendRequestForSeed is executed
    function test_baskets_sendRequestForSeed() public {
        
        // ~ Config ~

        vm.prank(factoryOwner);
        uint256 requestId = basket.sendRequestForSeed();
        assertEq(requestId, 0); // nothing happens. No NFTs deposited

        // Joe deposits so depositedTnfts.length > 0
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // ~ Pre-state check ~

        assertEq(basket.seedRequestInFlight(), false);
        assertEq(basket.pendingSeedRequestId(), 0);

        // ~ Execute sendRequestForSeed ~

        vm.prank(factoryOwner);
        requestId = basket.sendRequestForSeed();

        // ~ Post-state check 1 ~

        assertEq(basket.seedRequestInFlight(), true);
        assertEq(basket.pendingSeedRequestId(), requestId);

        // ~ Vrf responds with callback ~

        //_mockVrfCoordinatorResponse(address(basket), 10);
        basketVrfConsumer.fulfillRandomnessTestnet(10, requestId);

        // ~ Post-state check 1 ~

        assertEq(basket.seedRequestInFlight(), false);
        assertEq(basket.pendingSeedRequestId(), 0);
    }


    // ~ updatePrimaryRentToken ~

    /// @notice Verifies proper state changes when Basket::updatePrimaryRentToken is executed
    function test_baskets_updatePrimaryRentToken() public {

        // ~ Pre-state check ~

        assertEq(address(basket.primaryRentToken()), address(DAI_MOCK));

        // ~ Execute updatePrimaryRentToken ~

        vm.prank(factoryOwner);
        basket.updatePrimaryRentToken(address(UNREAL_USDC), false);

        // ~ Post-state check ~

        assertEq(address(basket.primaryRentToken()), address(UNREAL_USDC));
    }

    /// @notice Verifies restritions when Basket::updatePrimaryRentToken is executed
    function test_baskets_updatePrimaryRentToken_restrictions() public {
        // Cannot be address(0)
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.ZeroAddress.selector));
        basket.updatePrimaryRentToken(address(0), false);

        // force disableRebase failure
        bytes memory data = abi.encodeWithSignature("disableRebase(address,bool)", address(basket), true);
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.LowLevelCallFailed.selector, data));
        basket.updatePrimaryRentToken(address(DAI_MOCK), true);
    }

    /// @notice Verifies proper state changes when Basket::updatePrimaryRentToken is executed and the new token is a rebase token
    function test_baskets_USTB_updatePrimaryRentToken_isRebaseToken() public {

        // ~ Pre-state check ~

        assertEq(address(basket.primaryRentToken()), address(DAI_MOCK));
        assertEq(IUSTB(address(Unreal_USTB)).optedOut(address(basket)), false);

        // ~ Execute updatePrimaryRentToken ~

        vm.prank(factoryOwner);
        basket.updatePrimaryRentToken(address(Unreal_USTB), true);

        // ~ Post-state check ~

        assertEq(address(basket.primaryRentToken()), address(Unreal_USTB));
        assertEq(IUSTB(address(Unreal_USTB)).optedOut(address(basket)), true);
    }

    /// @notice Verifies proper state changes during rebase after rent token change
    function test_baskets_updateRent_thenRebase() public {

        // ~ Config ~

        uint256 amountRent = 10_000 * WAD;
        uint256 amountRentUSDC = 10_000 * USD;

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
        deal(address(DAI_MOCK), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        DAI_MOCK.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(DAI_MOCK),
            amountRent,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // skip to end of vesting period
        skip(1);


        // ~ Sanity check ~

        uint256 rentClaimable = rentManager.claimableRentForToken(tokenId);
        assertEq(rentClaimable, amountRent);
        assertEq(basket.tokenDeposited(address(realEstateTnft), tokenId), true);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), 0);

        // ~ Pre-state check ~

        uint256 increaseRatio = (amountRent * 1e18) / basket.getTotalValueOfBasket();
        emit log_named_uint("% increase post-rebase", increaseRatio); // 76923 == 7.6923%

        uint256 preTotalValue = basket.getTotalValueOfBasket();
        uint256 preTotalSupply = basket.totalSupply();

        assertEq(preTotalSupply, basket.balanceOf(ALICE));

        emit log_named_uint("total supply", basket.totalSupply());     // 129350000000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 130000000000000000000000

        // ~ rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase(); // Index -> 1.069230769230769230

        // fee taken: 1000.000000000000000000
        // total rent val: 9000.000000000000000000

        // ~ Post-state check ~

        uint256 postRebaseSupply = preTotalSupply + ((preTotalSupply * (amountRent - ((amountRent * basket.rentFee()) / 100_00))) / preTotalValue);

        assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
        assertGt(basket.totalSupply(), preTotalSupply);
        assertGt(basket.getTotalValueOfBasket(), preTotalValue);
        assertWithinDiff(
            basket.totalSupply(),
            postRebaseSupply,
            1e16
        ); // deviation of .01 or lower is acceptable
        uint256 totalRentValue = basket.totalRentValue();
        assertEq(basket.getRentBal(), totalRentValue);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRent * basket.rentFee()) / 100_00);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + totalRentValue, amountRent);
 
        emit log_named_uint("decimals diff", basket.decimalsDiff());
        emit log_named_uint("total supply", basket.totalSupply());     // 139299999999999999990050
        emit log_named_uint("total supply prediction", postRebaseSupply);     // 139300000000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 139000000000000000000000

        // ~ Withdraw all rent from basket ~

        vm.startPrank(factoryOwner);
        basket.withdrawRent(basket.totalRentValue());
        vm.stopPrank();

        assertEq(basket.getRentBal(), 0); // rent value is 0
        assertEq(basket.totalRentValue(), 0); // but `totalRentValue` is unchanged

        // ~ Admin changes primaryRentToken ~

        vm.prank(factoryOwner);
        basket.updatePrimaryRentToken(address(UNREAL_USDC), false);

        // ~ Exchange previous primaryRentToken ~

        // exchange USTB for USDC
        // Transfer all USDC into basket
        deal(address(UNREAL_USDC), address(basket), amountRentUSDC);

        // ~ Rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase(); // Index -> 1.138461538461538460

        // fee taken: 1000.000000
        // total rent val: 9000.000000

        // ~ Post-state check ~

        postRebaseSupply = preTotalSupply + ((preTotalSupply * (amountRentUSDC - ((amountRentUSDC * basket.rentFee()) / 100_00))) / preTotalValue);

        assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
        assertGt(basket.totalSupply(), preTotalSupply);
        assertGt(basket.getTotalValueOfBasket(), preTotalValue);

        totalRentValue = basket.totalRentValue();
        assertEq(basket.getRentBal(), totalRentValue);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRentUSDC * basket.rentFee()) / 100_00);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + totalRentValue, amountRentUSDC);
 
        emit log_named_uint("decimals diff", basket.decimalsDiff());
        emit log_named_uint("total supply", basket.totalSupply());     // 1472599999999999998010
        emit log_named_uint("total supply prediction", postRebaseSupply);     // 1383050000000000000000
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());  // 139000000000000000000000
    }

    /// @notice Verifies state when Basket::reinvestRent is executed.
    function test_baskets_reinvestRent() public {
        // ~ Config ~

        uint256 amountRent = 10_000 * WAD;

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
        deal(address(DAI_MOCK), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        DAI_MOCK.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(DAI_MOCK),
            amountRent,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // skip to end of vesting period
        skip(1);


        // ~ Sanity check ~

        uint256 rentClaimable = rentManager.claimableRentForToken(tokenId);
        assertEq(rentClaimable, amountRent);
        assertEq(basket.tokenDeposited(address(realEstateTnft), tokenId), true);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), 0);

        // ~ Pre-state check ~

        uint256 increaseRatio = (amountRent * 1e18) / basket.getTotalValueOfBasket();
        emit log_named_uint("% increase post-rebase", increaseRatio); // 76923 == 7.6923%

        uint256 preTotalValue = basket.getTotalValueOfBasket();
        uint256 preTotalSupply = basket.totalSupply();

        assertEq(preTotalSupply, basket.balanceOf(ALICE));

        // ~ rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase(); // Index -> 1.069230769230769230

        // fee taken: 1000.000000000000000000
        // total rent val: 9000.000000000000000000

        // ~ Post-state check ~

        uint256 postRebaseSupply = preTotalSupply + ((preTotalSupply * (amountRent - ((amountRent * basket.rentFee()) / 100_00))) / preTotalValue);

        assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
        assertGt(basket.totalSupply(), preTotalSupply);
        assertGt(basket.getTotalValueOfBasket(), preTotalValue);
        assertWithinDiff(
            basket.totalSupply(),
            postRebaseSupply,
            1e16
        ); // deviation of .01 or lower is acceptable
        uint256 totalRentValue = basket.totalRentValue();
        assertEq(basket.getRentBal(), totalRentValue);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRent * basket.rentFee()) / 100_00);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + totalRentValue, amountRent);

        // ~ Owner calls reinvestRent ~

        // create new NFT
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, //100k gbp
            1,
            1,
            2, // fingerprint
            address(this)
        );
        tokenId = tokenIds[0];

        address target = address(this);

        vm.prank(factoryOwner);
        basket.addTrustedTarget(target, true);

        uint256 rentBalance = 1_000 * WAD;
        bytes memory data = abi.encodeWithSignature("reinvestNoDeposit(address,address,uint256)", address(basket), address(DAI_MOCK), rentBalance);

        // if value does not increase, revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.TotalValueDecreased.selector));
        basket.reinvestRent(target, rentBalance, data);

        data = abi.encodeWithSignature("reinvest(address,address,uint256,uint256)", address(basket), address(DAI_MOCK), rentBalance, tokenId);
        
        vm.prank(factoryOwner);
        basket.reinvestRent(target, rentBalance, data); // Index -> 1.069230769230769230

        // ~ Post-state check ~

        assertEq(basket.getRentBal(), totalRentValue - rentBalance);

        // ~ Deal rent to basket and rebase ~

        deal(address(DAI_MOCK), address(this), 100 * WAD);
        DAI_MOCK.transfer(address(basket), 100 * WAD);

        assertEq(basket.getRentBal(), (totalRentValue - rentBalance) + (100 * WAD));

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase(); // Index -> 1.069566590126291618
    }

    /// @notice Verifies restrictions when Basket::reinvestRent is executed.
    function test_baskets_reinvestRent_restrictions() public {
        address target = address(this);

        uint256 rentBalance = 1_000 * WAD;
        bytes memory data;

        // create token of certain value
        _createItemAndMint(
            address(realEstateTnft),
            100_000_000, //100k gbp
            1,
            1,
            1, // fingerprint
            ALICE
        );

        // cannot call target that has not been added as trusted
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.InvalidTarget.selector, target));
        basket.reinvestRent(target, rentBalance, data);

        vm.prank(factoryOwner);
        basket.addTrustedTarget(target, true);

        // if low level call fails, revert
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.LowLevelCallFailed.selector, data));
        basket.reinvestRent(target, rentBalance, data);
    }


    // ~ setters ~

    /// @notice Verifies proper state changes when Basket::updateRentFee is executed.
    function test_baskets_updateRentFee() public {

        // ~ Pre-state check

        assertEq(basket.rentFee(), 10_00);

        // ~ Execute updateRentFee ~

        vm.prank(factoryOwner);
        basket.updateRentFee(20_00);

        // ~ Post-state check

        assertEq(basket.rentFee(), 20_00);
    }

    /// @notice Covers all necessary restrictions when Basket::updateRentFee is executed.
    function test_baskets_updateRentFee_restrictions() public {
        // rent fee cannot exceed 50% (50_00)
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.FeeTooHigh.selector, 60_00));
        basket.updateRentFee(60_00);

        // bob cannot call updateRentFee
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basket.updateRentFee(20_00);
    }

    /// @notice Verifies proper state changes when Basket::setWithdrawRole is executed.
    function test_baskets_setWithdrawRole() public {

        // ~ Pre-state check

        assertEq(basket.canWithdraw(BOB), false);

        // ~ Execute setWithdrawRole ~

        vm.prank(factoryOwner);
        basket.setWithdrawRole(BOB, true);

        // ~ Post-state check

        assertEq(basket.canWithdraw(BOB), true);
    }

    /// @notice Covers all necessary restrictions when Basket::setWithdrawRole is executed.
    function test_baskets_setWithdrawRole_restrictions() public {
        // cannot call with address(0)
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.ZeroAddress.selector));
        basket.setWithdrawRole(address(0), true);

        // bob cannot call updateRentFee
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basket.setWithdrawRole(BOB, true);
    }

    /// @notice Verifies proper state when BasketsVrfConsumer::updateOperator is called.
    function test_baskets_basketsVrfConsumer_updateOperator() public {
        assertEq(basketVrfConsumer.operator(), GELATO_OPERATOR);
        vm.prank(factoryOwner);
        basketVrfConsumer.updateOperator(JOE);
        assertEq(basketVrfConsumer.operator(), JOE);
    }

    /// @notice Verifies restrictions when BasketsVrfConsumer::updateOperator is called.
    function test_baskets_basketsVrfConsumer_updateOperator_restrictions() public {
        // cannot call with address(0)
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(BasketsVrfConsumer.ZeroAddress.selector));
        basketVrfConsumer.updateOperator(address(0));

        // bob cannot call updateRentFee
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basketVrfConsumer.updateOperator(JOE);
    }

    /// @notice Verifies proper state when Basket::addTrustedTarget is called.
    function test_baskets_addTrustedTarget() public {
        assertEq(basket.trustedTarget(BOB), false);
        vm.prank(factoryOwner);
        basket.addTrustedTarget(BOB, true);
        assertEq(basket.trustedTarget(BOB), true);
    }

    /// @notice Verifies restrictions when Basket::addTrustedTarget is called
    function test_baskets_addTrustedTarget_restrictions() public {
        // cannot call with address(0)
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(IBasket.ZeroAddress.selector));
        basket.addTrustedTarget(address(0), true);

        // bob cannot call updateRentFee
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basket.addTrustedTarget(BOB, true);
    }

    /// @notice Verifies proper state when Basket::updateCap is called.
    function test_baskets_updateCap() public {
        assertEq(basket.cap(), 500);
        vm.prank(factoryOwner);
        basket.updateCap(600);
        assertEq(basket.cap(), 600);
    }

    /// @notice Verifies restrictions when Basket::updateCap is called
    function test_baskets_updateCap_restrictions() public {
        // bob cannot call updateRentFee
        vm.prank(BOB);
        vm.expectRevert(bytes("NFO"));
        basket.updateCap(600);
    }

    /// @notice Verifies proper state changes when CurrencyCalculator::updateExchangeRateOracleMaxAge is called.
    function test_baskets_currencyCalculator_updateExchangeRateOracleMaxAge() public {
        assertNotEq(currencyCalculator.exchangeRateOracleMaxAge(), 1 days);
        vm.prank(factoryOwner);
        currencyCalculator.updateExchangeRateOracleMaxAge(1 days);
        assertEq(currencyCalculator.exchangeRateOracleMaxAge(), 1 days);
    }

    /// @notice Verifies proper restrictions when CurrencyCalculator::updateExchangeRateOracleMaxAge is called.
    function test_baskets_currencyCalculator_updateExchangeRateOracleMaxAge_restrictions() public {
        // Cannot set maxAge to 0
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(CurrencyCalculator.ZeroValue.selector));
        currencyCalculator.updateExchangeRateOracleMaxAge(0);
    }

    /// @notice Verifies proper state changes when CurrencyCalculator::updatePriceOracleMaxAge is called.
    function test_baskets_currencyCalculator_updatePriceOracleMaxAge() public {
        assertNotEq(currencyCalculator.priceOracleMaxAge(), 1 days);
        vm.prank(factoryOwner);
        currencyCalculator.updatePriceOracleMaxAge(1 days);
        assertEq(currencyCalculator.priceOracleMaxAge(), 1 days);
    }

    /// @notice Verifies restrictions when CurrencyCalculator::updatePriceOracleMaxAge is called.
    function test_baskets_currencyCalculator_updatePriceOracleMaxAge_restrictions() public {
        // Cannot set maxAge to 0
        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSelector(CurrencyCalculator.ZeroValue.selector));
        currencyCalculator.updatePriceOracleMaxAge(0);
    }

    /// @notice Verifies restrictions when CurrencyCalculator::getTnftNativeValue is called.
    function test_baskets_currencyCalculator_getTnftNativeValue_restrictions() public {
        vm.prank(factoryOwner);
        currencyCalculator.updatePriceOracleMaxAge(1);
        skip(100);

        uint256 fp = ITangibleNFT(address(realEstateTnft)).tokensFingerprint(JOE_TOKEN_ID);

        vm.expectRevert();
        currencyCalculator.getTnftNativeValue(address(realEstateTnft), fp);
    }

    /// @notice Verifies proper state when initializing a CurrencyCalculator contract.
    function test_baskets_currencyCalculator_initializer() public {
        CurrencyCalculator newCC = new CurrencyCalculator();

        ERC1967Proxy newCCProx = new ERC1967Proxy(
            address(newCC),
            abi.encodeWithSelector(CurrencyCalculator.initialize.selector,
                address(factoryV2),
                24 hours,
                31 days
            )
        );
        newCC = CurrencyCalculator(address(newCCProx));

        assertEq(newCC.factory(), address(factoryV2));
        assertEq(newCC.exchangeRateOracleMaxAge(), 24 hours);
        assertEq(newCC.priceOracleMaxAge(), 31 days);
    }
}