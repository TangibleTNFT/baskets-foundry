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
contract BasketsUSTBIntegrationTest is Utility {

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

    // proxies
    ERC1967Proxy public basketManagerProxy;
    ERC1967Proxy public vrfConsumerProxy;

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
    IERC20 public USTB = IERC20(Unreal_USTB);

    uint256[] internal preMintedTokens;

    /// @notice Config function for test cases.
    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);
        emit log_uint(block.chainid);

        factoryOwner = IOwnable(address(factoryV2)).owner();

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
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(USTB),
                true,
                address(currencyCalculator)
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
        _createLabels();
    }


    // -------
    // Utility
    // -------

    /// @notice Creates labels for addresses. Makes traces easier to read.
    function _createLabels() internal override {
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
        super._createLabels();
    }

    /// @dev local deal to take into account USTB's unique storage layout
    function _deal(address token, address give, uint256 amount) internal {
        // deal doesn't work with USTB since the storage layout is different
        if (token == Unreal_USTB) {
            // if address is opted out, update normal balance (basket is opted out of rebasing)
            if (give == address(basket)) {
                bytes32 USTBStorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;
                uint256 mapSlot = 0;
                bytes32 slot = keccak256(abi.encode(give, uint256(USTBStorageLocation) + mapSlot));
                vm.store(Unreal_USTB, slot, bytes32(amount));
            }
            // else, update shares balance
            else {
                bytes32 USTBStorageLocation = 0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;
                uint256 mapSlot = 2;
                bytes32 slot = keccak256(abi.encode(give, uint256(USTBStorageLocation) + mapSlot));
                vm.store(Unreal_USTB, slot, bytes32(amount));
            }
        }
        // If not rebase token, use normal deal
        else {
            deal(token, give, amount);
        }
    }

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


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test.
    function test_baskets_USTB_init_state() public {
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

    /// @notice Verifies redeem math -> proposed by Daniel.
    function test_baskets_USTB_redeemTNFT_math() public {

        // ~ Conig ~

        // deal category owner USDC to deposit into rentManager
        uint256 aliceRentBal = 10 * WAD;
        uint256 bobRentBal = 5 * WAD;
        _deal(address(USTB), TANGIBLE_LABS, aliceRentBal + bobRentBal);

        uint256 preBalRentManager = USTB.balanceOf(address(rentManager));

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
        USTB.approve(address(rentManager), aliceRentBal);
        rentManager.deposit(
            aliceToken,
            address(USTB),
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
        USTB.approve(address(rentManager), bobRentBal);
        rentManager.deposit(
            bobToken,
            address(USTB),
            bobRentBal,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // skip to end of vesting

        // Sanity rent check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * WAD);
        assertApproxEqAbs(rentManager.claimableRentForToken(bobToken), 5 * WAD, 1);

        assertEq(USTB.balanceOf(address(rentManager)), preBalRentManager + (15 * WAD));
        assertEq(USTB.balanceOf(address(basket)), 0);
        assertEq(USTB.balanceOf(ALICE), 0);
        assertEq(USTB.balanceOf(BOB), 0);

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
        assertApproxEqAbs(rentManager.claimableRentForToken(bobToken), 5 * WAD, 1);

        assertEq(USTB.balanceOf(address(rentManager)), preBalRentManager + (5 * WAD));
        assertEq(USTB.balanceOf(address(basket)), 10 * WAD);
        assertEq(USTB.balanceOf(ALICE), 0);
        assertEq(USTB.balanceOf(BOB), 0);

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
    function test_baskets_USTB_checkPrecision_rent_fuzzing(uint256 _value, uint256 _rent) public {
        _value = bound(_value, 1000, 100_000_000_000); // range (1 -> 100M) decimals = 3
        _rent  = bound(_rent, 1 * 1e18, 1_000_000 * 1e18); // range (1 -> 1M) decimals = 18

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

        // _deal rent to basket
        _deal(address(USTB), address(basket), _rent);

        // sanity check
        assertGt(USTB.balanceOf(address(basket)), 0);
        uint256 rentBal = USTB.balanceOf(address(basket));
        assertEq(USTB.balanceOf(JOE), 0);

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

        assertEq(USTB.balanceOf(address(basket)), rentBal);
        assertEq(USTB.balanceOf(JOE), 0);

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

        assertEq(USTB.balanceOf(address(basket)), rentBal);
        assertEq(USTB.balanceOf(JOE), 0);

        assertEq(basket.balanceOf(JOE), preBasketBalJoe - quoteOut);
        assertEq(basket.totalSupply(),  basket.balanceOf(JOE));
    }


    // ----------------------
    // View Method Unit Tests
    // ----------------------

    // ~ getTotalValueOfBasket ~
    
    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket
    function test_baskets_USTB_getTotalValueOfBasket_single() public {

        assertEq(basket.getTotalValueOfBasket(), 0);

        // deposit TNFT of certain value -> $650k usd
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // get nft value
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        assertEq(usdValue1, 655_000 ether);

        emit log_uint(USTB.balanceOf(TANGIBLE_LABS));

        // _deal category owner USTB to deposit into rentManager
        uint256 amount = 10_000 * WAD;
        _deal(address(USTB), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        USTB.approve(address(rentManager), amount);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(USTB),
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

        // grab rent value
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertApproxEqAbs(basket.getRentBal(), rentClaimable - ((rentClaimable * basket.rentFee()) / 100_00), 1);
        assertApproxEqAbs(totalValue, usdValue1 + (basket.getRentBal() * basket.decimalsDiff()), 1);
        assertApproxEqAbs(basket.getRentBal(), basket.totalRentValue(), 1);
    }

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket with many TNFTs.
    function test_baskets_USTB_getTotalValueOfBasket_multiple() public {

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

        // _deal category owner USDC to deposit into rentManager for tnft 1 and tnft 2
        uint256 amount1 = 10_000 * WAD;
        uint256 amount2 = 14_000 * WAD;
        _deal(address(USTB), TANGIBLE_LABS, amount1 + amount2);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        // deposit rent for tnft 1
        USTB.approve(address(rentManager), amount1);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(USTB),
            amount1,
            0,
            block.timestamp + 1,
            true
        );
        // deposit rent for tnft 2
        USTB.approve(address(rentManager), amount2);
        rentManager.deposit(
            NIK_TOKEN_ID,
            address(USTB),
            amount2,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        skip(1); // go to end of vesting period

        // get claimable rent value for tnft 1
        uint256 rentClaimable1 = rentManager.claimableRentForToken(JOE_TOKEN_ID);
        assertApproxEqAbs(rentClaimable1, amount1, 1);

        // get claimable rent value for tnft 2
        uint256 rentClaimable2 = rentManager.claimableRentForToken(NIK_TOKEN_ID);
        assertApproxEqAbs(rentClaimable2, amount2, 1);

        uint256 totalRent = rentClaimable1 + rentClaimable2;

        // grab rent value
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertApproxEqAbs(basket.getRentBal(), totalRent - ((totalRent * basket.rentFee()) / 100_00), 1);
        assertApproxEqAbs(totalValue, usdValue1 + usdValue2 + (basket.getRentBal() * basket.decimalsDiff()), 1);
        assertApproxEqAbs(basket.getRentBal(), basket.totalRentValue(), 1);
    }


    // ~ withdrawRent ~

    /// @notice Verifies proper state change upon a successful execution of Basket::withdrawRent.
    function test_baskets_USTB_withdrawRent() public {

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

        // _deal category owner USDC to deposit into rentManager
        uint256 amount = 10_000 * WAD;
        //uint256 fullRentAmount = amount * 2;

        _deal(address(USTB), TANGIBLE_LABS, amount);

        // deposit rent for that TNFT (no vesting)
        vm.startPrank(TANGIBLE_LABS);
        USTB.approve(address(rentManager), amount);
        rentManager.deposit(
            JOE_TOKEN_ID,
            address(USTB),
            amount,
            0,
            block.timestamp + 1,
            true
        );
        vm.stopPrank();

        // go to end of vesting period
        skip(1);

        // also _deal USDC straight into the basket
        _deal(address(USTB), address(basket), amount);

        // ~ Sanity check ~

        uint256 basketBal = USTB.balanceOf(address(basket));

        assertEq(basket.getRentBal(), basketBal + amount);
        uint256 preBalOwner = basket.primaryRentToken().balanceOf(factoryOwner);
        uint256 preBalRevDist = basket.primaryRentToken().balanceOf(basketManager.revenueDistributor());

        uint256 revSharePortion = ((amount + basketBal) * basket.rentFee()) / 100_00;
        uint256 withdrawable = (amount + basketBal) - revSharePortion;

        // ~ Rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // ~ Pre-state check ~

        assertApproxEqAbs(basket.getRentBal(), withdrawable, 1);
        assertApproxEqAbs(basket.totalRentValue(), withdrawable, 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), preBalRevDist + revSharePortion, 1);

        // ~ Execute withdrawRent ~

        // Force revert
        vm.prank(factoryOwner);
        vm.expectRevert();
        basket.withdrawRent(type(uint256).max);

        vm.prank(factoryOwner);
        basket.withdrawRent(withdrawable);

        // ~ Post-state check ~

        assertApproxEqAbs(basket.getRentBal(), 0, 2);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(factoryOwner), preBalOwner + withdrawable, 1);
    }

    
    // ~ rebasing ~

    /// @notice Verifies proper state changes during rebase
    function test_baskets_USTB_rebase() public {

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
        _deal(address(USTB), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        USTB.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(USTB),
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
        assertApproxEqAbs(basket.getRentBal(), basket.totalRentValue(), 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRent * basket.rentFee()) / 100_00, 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + basket.totalRentValue(), amountRent, 1);
 
        emit log_named_uint("decimals diff", basket.decimalsDiff());
        emit log_named_uint("total supply", basket.totalSupply());
        emit log_named_uint("total supply prediction", postRebaseSupply);
        emit log_named_uint("basket value", basket.getTotalValueOfBasket());
    }

    /// @notice Verifies correct state changes when disableRebase is executed.
    function test_baskets_USTB_disableRebase() public {

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

    /// @notice Verifies the overall value of the basket can decrease and as long as rent has increased, rebase is positive.
    function test_baskets_USTB_decreaseValue_thenRebase() public {

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

        // _deal category owner USDC to deposit into rentManager for tnft 1 and tnft 2
        uint256 amount = 10_000 * WAD;
        _deal(address(USTB), TANGIBLE_LABS, amount);

        assert(USTB.balanceOf(TANGIBLE_LABS) >= amount);
        
        vm.prank(TANGIBLE_LABS);
        USTB.transfer(address(basket), amount);

        // grab rent value
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();

        // post state check 1
        uint256 totalValue = basket.getTotalValueOfBasket();
        emit log_named_uint("Total value of basket 1", totalValue);
        assertApproxEqAbs(totalValue, usdValue1 + usdValue2 + (basket.getRentBal() * basket.decimalsDiff()), 1);
        assertApproxEqAbs(basket.getRentBal(), basket.totalRentValue(), 1);

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
        assertApproxEqAbs(totalValue, usdValue2 + (basket.getRentBal() * basket.decimalsDiff()), 1);

        uint256 preRebaseIndex = basket.rebaseIndex();

        // try to rebase
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();
        assertEq(basket.rebaseIndex(), preRebaseIndex); // rebaseIndex does not change

        // deposit a bit more rent
        amount = 10 ether;
        _deal(address(USTB), TANGIBLE_LABS, amount);
        vm.prank(TANGIBLE_LABS);
        USTB.transfer(address(basket), amount);

        // rebase
        preRebaseIndex = basket.rebaseIndex();

        // rebase
        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();
        assertGt(basket.rebaseIndex(), preRebaseIndex); // rebaseIndex should be larger
    }


    // ~ updatePrimaryRentToken ~

    /// @notice Verifies proper state changes during rebase after rent token change
    function test_baskets_USTB_updateRent_thenRebase() public {

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
        _deal(address(USTB), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        USTB.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(USTB),
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
        assertApproxEqAbs(basket.getRentBal(), totalRentValue, 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRent * basket.rentFee()) / 100_00, 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + totalRentValue, amountRent, 1);

        // ~ Withdraw all rent from basket ~

        vm.startPrank(factoryOwner);
        basket.withdrawRent(basket.totalRentValue());
        vm.stopPrank();

        assertApproxEqAbs(basket.getRentBal(), 0, 2);
        assertEq(basket.totalRentValue(), 0); // but `totalRentValue` is unchanged

        // ~ Admin changes primaryRentToken ~

        vm.prank(factoryOwner);
        basket.updatePrimaryRentToken(address(UNREAL_USDC), false);

        // ~ Exchange previous primaryRentToken ~

        // exchange USTB for USDC
        // Transfer all USDC into basket
        _deal(address(UNREAL_USDC), address(basket), amountRentUSDC);

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
    }

    /// @notice Verifies state when Basket::reinvestRent is executed.
    function test_baskets_USTB_reinvestRent() public {
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
        _deal(address(USTB), TANGIBLE_LABS, amountRent);

        vm.startPrank(TANGIBLE_LABS);
        USTB.approve(address(rentManager), amountRent);
        rentManager.deposit(
            tokenId,
            address(USTB),
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
        assertApproxEqAbs(basket.getRentBal(), totalRentValue, 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (amountRent * basket.rentFee()) / 100_00, 1);
        assertApproxEqAbs(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + totalRentValue, amountRent, 1);

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
        bytes memory data = abi.encodeWithSignature("reinvest(address,address,uint256,uint256)", address(basket), address(USTB), rentBalance, tokenId);

        vm.prank(factoryOwner);
        basket.reinvestRent(target, rentBalance, data); // Index -> 1.069230769230769230

        // ~ Post-state check ~

        assertApproxEqAbs(basket.getRentBal(), totalRentValue - rentBalance, 2);


        // ~ Deal rent to basket and rebase ~

        _deal(address(USTB), address(this), 100 * WAD);
        USTB.transfer(address(basket), 100 * WAD);

        assertApproxEqAbs(basket.getRentBal(), (totalRentValue - rentBalance) + (100 * WAD), 2);

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase(); // Index -> 1.069566590126291618
    }
}