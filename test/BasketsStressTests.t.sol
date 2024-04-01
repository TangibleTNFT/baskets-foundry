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
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC1967Utils, ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// tangible contract imports
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { MockMatrixOracle } from "@tangible/tests/mocks/MockMatrixOracle.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";

// tangible interface imports
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";
import { INotificationWhitelister } from "@tangible/interfaces/INotificationWhitelister.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { CurrencyCalculator } from "../src/CurrencyCalculator.sol";
import { BasketManager } from "../src/BasketManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "../src/interfaces/IGetNotificationDispatcher.sol";

// local helper contracts
import "./utils/MumbaiAddresses.sol";
import "./utils/UnrealAddresses.sol";
import "./utils/Utility.sol";


/**
 * @title StressTests
 * @author Chase Brown
 * @notice This test file is for "stress" testing. Advanced testing methods and integration tests combined to identify
 *         the stability of the baskets protocol.
 * @dev This testing file takes advantage of Foundry's advanced Fuzz testing tools.
 */
contract StressTests is Utility {

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
    ProxyAdmin public proxyAdmin;

    // ~ Actors and Variables ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public TANGIBLE_LABS; // NOTE: category owner

    ERC20Mock public DAI_MOCK;

    address public rentManagerDepositor = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    mapping(address => uint256[]) internal tokenIdMap;

    // For avoiding stack too deep errors
    struct TestConfig {
        uint256 newCategories;
        uint256 amountFingerprints;
        uint256 totalTokens;
        uint256 rent;
        uint256[] fingerprints;
        address[] tnfts;
        uint256[] rentArr;
    }

    TestConfig config;


    /// @notice Unit test config method
    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).owner();
        proxyAdmin = new ProxyAdmin(address(this));

        ERC20Mock dai = new ERC20Mock();
        DAI_MOCK = dai;

        // new category owner
        TANGIBLE_LABS = factoryV2.categoryOwner(ITangibleNFT(realEstateTnft));

        // basket stuff
        basket = new Basket();

        // Deploy CurrencyCalculator -> not upgradeable
        currencyCalculator = new CurrencyCalculator(address(factoryV2));
        
        // Deploy basketManager
        basketManager = new BasketManager();

        // Deploy proxy for basketManager -> initialize
        basketManagerProxy = new ERC1967Proxy(
            address(basketManager),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2),
                address(DAI_MOCK),
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
                GELATO_OPERATOR,
                80001
            )
        );
        basketVrfConsumer = BasketsVrfConsumer(address(vrfConsumerProxy));

        // set basketVrfConsumer address on basketManager
        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        // set revenueShare address on basketManager
        vm.prank(factoryOwner);
        basketManager.setRevenueDistributor(REV_SHARE); // NOTE: Should be replaced with real rev share contract

        vm.prank(TANGIBLE_LABS); // category owner
        notificationDispatcher.addWhitelister(address(basketManager));

        // updateDepositor for rent manager
        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(TANGIBLE_LABS);

        // set basketManager
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // set currencyFeed
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        // set rebase controller
        vm.prank(factoryOwner);
        basketManager.setRebaseController(REBASE_CONTROLLER);

        vm.startPrank(ORACLE_OWNER);
        // set tangibleWrapper to be real estate oracle on chainlink oracle.
        IPriceOracleExt(address(chainlinkRWAOracle)).setTangibleWrapperAddress(
            address(realEstateOracle)
        );
        vm.stopPrank();

        vm.startPrank(factoryOwner);
        // add feature to metadata contract
        ITNFTMetadataExt(address(metadata)).addFeatures(
            _asSingletonArrayUint(RE_FEATURE_1),
            _asSingletonArrayString("Beach Homes")
        );
        // add feature to TNFTtype in metadata contract
        ITNFTMetadataExt(address(metadata)).addFeaturesForTNFTType(
            RE_TNFTTYPE,
            _asSingletonArrayUint(RE_FEATURE_1)
        );
        vm.stopPrank();

        //emit log_named_address("Oracle for category", address(priceManager.oracleForCategory(realEstateTnft)));

        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1), true);
        emit log_named_bool("Fingerprint added:", (ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1)));

        vm.prank(ORACLE_OWNER);
        chainlinkRWAOracle.updateStock(
            RE_FINGERPRINT_1,
            1
        );

        uint256[] memory tokenIds = _mintToken(address(realEstateTnft), 1, RE_FINGERPRINT_1, CREATOR);

        // Deploy basket
        uint256[] memory features = new uint256[](0);
        
        vm.startPrank(CREATOR);
        realEstateTnft.approve(address(basketManager), tokenIds[0]);
        (IBasket _basket,) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            0,
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(tokenIds[0])
        );
        vm.stopPrank();

        basket = Basket(address(_basket));

        // creator redeems token to isolate tests.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(basket.balanceOf(CREATOR), keccak256(abi.encodePacked(address(realEstateTnft), tokenIds[0])));
        vm.stopPrank();

        // rebase controller sets the rebase manager.
        vm.prank(REBASE_CONTROLLER);
        basket.updateRebaseIndexManager(REBASE_INDEX_MANAGER);

        // init state check
        assertEq(basket.totalSupply(), 0);

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
        //vm.label(address(vrfCoordinatorMock), "MOCK_VRF_COORDINATOR");
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

    /// @notice Helper function for creating items and minting to a designated address.
    function _createItemAndMint(address tnft, uint256 _sellAt, uint256 _stock, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        require(_mintCount >= _stock, "mint count must be gt stock");

        IPriceOracle oracle = priceManager.oracleForCategory(ITangibleNFT(tnft));
        IChainlinkRWAOracle chainlinkOracle = IPriceOracleExt(address(oracle)).chainlinkRWAOracle();

        // create new item with fingerprint.
        vm.prank(ORACLE_OWNER);
        IPriceOracleExt(address(chainlinkOracle)).createItem(
            _fingerprint, // fingerprint
            _sellAt,      // weSellAt
            0,            // lockedAmount
            _stock,       // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );

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

    /// @notice helper function for adding new categories and deploying new TNFT addresses.
    function _deployNewTnftContract(string memory name) internal returns (address) {
        //a. deploy mockMatrix
        MockMatrixOracle mockMatrixOracle = new MockMatrixOracle();

        //b. deploy oracle
        RealtyOracleTangibleV2 realtyOracle = new RealtyOracleTangibleV2();
        TransparentUpgradeableProxy realtyOracleProxy = new TransparentUpgradeableProxy(
            address(realtyOracle),
            address(proxyAdmin),
            abi.encodeWithSelector(RealtyOracleTangibleV2.initialize.selector,
                address(factoryV2),
                address(currencyFeed),
                address(mockMatrixOracle)
            )
        );
        realtyOracle = RealtyOracleTangibleV2(address(realtyOracleProxy));

        // set oracle on mockMatrix
        mockMatrixOracle.setTangibleWrapperAddress(address(realtyOracle));

        //c.  Deploy TangibleNFTV2 -> for real estate
        vm.prank(TANGIBLE_LABS); // category owner
        ITangibleNFT tnft = IFactoryExt(address(factoryV2)).newCategory(
            name,  // Name
            name,     // Symbol
            "",         // Metadata base uri
            false,      // storage price fixed
            false,      // storage required
            address(realtyOracle), // oracle address
            false,      // symbol in uri
            RE_TNFTTYPE    // tnft type
        );

        //d. deploy ND
        RWAPriceNotificationDispatcher notifications = new RWAPriceNotificationDispatcher();
        TransparentUpgradeableProxy notificationsProxy = new TransparentUpgradeableProxy(
            address(notifications),
            address(proxyAdmin),
            abi.encodeWithSelector(RWAPriceNotificationDispatcher.initialize.selector,
                address(factoryV2),
                address(tnft)
            )
        );
        notifications = RWAPriceNotificationDispatcher(address(notificationsProxy));

        vm.startPrank(TANGIBLE_LABS);
        realtyOracle.setNotificationDispatcher(address(notifications));
        notifications.addWhitelister(address(basketManager));
        notifications.whitelistAddressAndReceiver(address(basket));
        vm.stopPrank();

        return address(tnft);
    }

    /// @notice This method runs through the same USDValue logic as the Basket::depositTNFT
    function _getUsdValueOfNft(address _tnft, uint256 _tokenId) internal view returns (uint256 usdValue) {

        IPriceOracle oracle = priceManager.oracleForCategory(ITangibleNFT(_tnft));
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = oracle.marketPriceNativeCurrency(fingerprint);
        // Fetch the string ISO code for currency
        string memory currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));
        // get decimal representation of property value
        uint256 oracleDecimals = oracle.decimals();
        
        // ~ get USD Exchange rate ~

        // fetch price feed contract for native currency
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currency);
        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // get decimal representation of exchange rate
        uint256 priceDecimals = priceFeed.decimals();
 
        // ~ get USD Value of property ~

        // calculate total USD value of property
        usdValue = (uint(price) * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
    }

    /// @notice Helper function for fetching notificationDispatcher contract given specific tnft contract.
    function _getNotificationDispatcher(address _tnft) internal returns (RWAPriceNotificationDispatcher) {
        IPriceOracle oracle = priceManager.oracleForCategory(ITangibleNFT(_tnft));
        return RWAPriceNotificationDispatcher(address(IGetNotificationDispatcher(address(oracle)).notificationDispatcher()));
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


    // ------------
    // Stress Tests
    // ------------


    // TODO:
    // a. deposit testing with multiple TNFT addresses and multiple tokens for each TNFT contract
    //    - test deposit and batch deposits with fuzzing
    //    - again, but with rent accruing -> changing share price
    //    - test deposit with rent vs deposit with no rent claimable
    //    - test what would happen if deployer immediately deposits 1-100 TNFTs at once
    // b. stress test redeemTNFT
    //    - 1000+ depositedTnfts
    // c. stress test _redeemRent
    //    - 10-100+ tnftsSupported DONE
    //    - refactor iterating thru claimable rent array and test multiple iterations with 100-1000+ TNFTs
    //    - test multiple redeems in succession.


    // ~ stress depositTNFT ~

    /// @notice Stress test of depositTNFT method.
    function test_stress_depositTNFT_single() public {
        
        // ~ Config ~

        config.newCategories = 4;
        config.amountFingerprints = 5;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        config.totalTokens = config.newCategories * config.amountFingerprints;

        uint256[] memory fingerprints = new uint256[](config.amountFingerprints);
        address[] memory tnfts = new address[](config.newCategories);

        // store all new fingerprints in array.
        uint256 i;
        for (i; i < config.amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        for (i = 0; i < config.newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
        }

        // mint multiple tokens for each contract
        for (i = 0; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute depositTNFT and Assert ~

        // deposit all tokens
        uint256 count;
        for (i = 0; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < tokenIdMap[tnft].length; ++j) {

                uint256 tokenId = tokenIdMap[tnft][j];
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);
                uint256 basketPreBal = basket.balanceOf(JOE);
                uint256 preTotalValue = basket.getTotalValueOfBasket();
                uint256 preValueGBP = basket.totalNftValueByCurrency("GBP");

                uint256 fingerprint = ITangibleNFT(tnft).tokensFingerprint(tokenId);
                (, uint256 nativeValue,) = currencyCalculator.getTnftNativeValue(tnft, fingerprint);
                uint256 usdValue = currencyCalculator.getUSDValue(tnft, tokenId);

                // get quotes for deposit
                uint256 quote = basket.getQuoteIn(tnft, tokenId);
                //uint256 feeTaken = _calculateFeeAmount(quote);

                // Joe executed depositTNFT
                vm.startPrank(JOE);
                ITangibleNFT(address(tnft)).approve(address(basket), tokenId);
                basket.depositTNFT(address(tnft), tokenId);
                vm.stopPrank();

                // verify share price * balance == totalValueOfBasket
                assertWithinPrecision(
                    (basket.balanceOf(JOE) * basket.getSharePrice()) / 1 ether,
                    basket.getTotalValueOfBasket(),
                    2
                );
                assertEq(basket.getTotalValueOfBasket(), preTotalValue + usdValue);
                assertEq(basket.totalNftValueByCurrency("GBP"), preValueGBP + nativeValue);

                // verify basket now owns token
                assertEq(ITangibleNFT(tnft).ownerOf(tokenId), address(basket));
                assertEq(basket.tokenDeposited(tnft, tokenId), true);

                // verify Joe balances
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal - 1);
                assertEq(basket.balanceOf(JOE), basketPreBal + quote);
                assertEq(basket.totalSupply(), basket.balanceOf(JOE));

                // verify notificationDispatcher state
                assertEq(
                    _getNotificationDispatcher(address(tnft)).registeredForNotification(address(tnft), tokenId),
                    address(basket)
                );
            }
        }

        // ~ Post-state check ~

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, config.totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, config.newCategories);

        count = 0;
        for (i = 0; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, config.amountFingerprints);

            for (uint256 j; j < tokenIdLib.length; ++j) {
                uint256 tokenId = tokenIdMap[tnftsSupported[i]][j];
                assertEq(tokenIdLib[j], tokenId);

                assertEq(deposited[count].tnft, tnftsSupported[i]);
                assertEq(deposited[count].tokenId, tokenId);
                assertEq(deposited[count].fingerprint, j);
                ++count;
            }
        }

        // reset tokenIdMap
        for (i = 0; i < config.newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of depositTNFT method using fuzzing.
    function test_stress_depositTNFT_fuzzing(uint256 _categories, uint256 _fps) public {
        _categories = bound(_categories, 1, 10);
        _fps = bound(_fps, 1, 20);

        // ~ Config ~

        config.newCategories = _categories;
        config.amountFingerprints = _fps;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        uint256[] memory fingerprints = new uint256[](config.amountFingerprints);
        address[] memory tnfts = new address[](config.newCategories);

        // store all new fingerprints in array.
        for (uint256 i; i < config.amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        for (uint256 i; i < config.newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
        }

        // mint multiple tokens for each contract
        for (uint256 i; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute depositTNFT and Assert ~

        // deposit all tokens
        for (uint256 i; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < tokenIdMap[tnft].length; ++j) {

                uint256 tokenId = tokenIdMap[tnft][j];
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);
                uint256 basketPreBal = basket.balanceOf(JOE);

                // get quotes for deposit
                uint256 quote = basket.getQuoteIn(tnft, tokenId);
                uint256 feeTaken = _calculateFeeAmount(quote);

                // Joe executed depositTNFT
                vm.startPrank(JOE);
                ITangibleNFT(address(tnft)).approve(address(basket), tokenId);
                basket.depositTNFT(address(tnft), tokenId);
                vm.stopPrank();

                // verify share price * balance == totalValueOfBasket
                assertWithinPrecision(
                    (basket.balanceOf(JOE) * basket.getSharePrice()) / 1 ether,
                    basket.getTotalValueOfBasket(),
                    2
                );

                // verify basket now owns token
                assertEq(ITangibleNFT(tnft).ownerOf(tokenId), address(basket));
                assertEq(basket.tokenDeposited(tnft, tokenId), true);

                // verify Joe balances
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal - 1);
                assertEq(basket.balanceOf(JOE), basketPreBal + quote);
                assertEq(basket.totalSupply(), basket.balanceOf(JOE));

                // verify share price is gt $100 per share
                assertGt(basket.getSharePrice(), 100 ether);

                // verify notificationDispatcher state
                assertEq(
                    _getNotificationDispatcher(address(tnft)).registeredForNotification(address(tnft), tokenId),
                    address(basket)
                );
            }
        }

        // ~ Post-state check ~

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, config.totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, config.newCategories);

        uint256 count;
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, config.amountFingerprints);

            for (uint256 j; j < tokenIdLib.length; ++j) {
                uint256 tokenId = tokenIdMap[tnftsSupported[i]][j];
                assertEq(tokenIdLib[j], tokenId);

                assertEq(deposited[count].tnft, tnftsSupported[i]);
                assertEq(deposited[count].tokenId, tokenId);
                assertEq(deposited[count].fingerprint, j);
                ++count;
            }
        }

        // reset tokenIdMap
        for (uint256 i; i < config.newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }


    // ~ stress batchDepositTNFT ~

    /// @notice Stress test of batchDepositTNFT method.
    /// NOTE: When num of tokens == 200, batchDepositTNFT consumes ~30.5M gas
    function test_stress_batchDepositTNFT_noFuzz() public {
        
        // ~ Config ~

        config.newCategories = 2;
        config.amountFingerprints = 10;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        uint256[] memory fingerprints = new uint256[](config.amountFingerprints);
        address[] memory tnfts = new address[](config.newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < config.amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < config.newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(batchTnftArr.length, config.totalTokens);
        assertEq(batchTokenIdArr.length, config.totalTokens);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute batchDepositTNFT ~

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        uint256 gas_start = gasleft();
        uint256[] memory shares = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);
        uint256 gas_used = gas_start - gasleft();
        vm.stopPrank();

        assertEq(shares.length, config.totalTokens);

        // ~ Post-state check ~

        // verify basket now owns token
        for (uint256 i; i < config.totalTokens; ++i) {
            assertEq(ITangibleNFT(batchTnftArr[i]).ownerOf(batchTokenIdArr[i]), address(basket));
            assertEq(basket.tokenDeposited(batchTnftArr[i], batchTokenIdArr[i]), true);

            // verify notificationDispatcher state
            assertEq(
                _getNotificationDispatcher(batchTnftArr[i]).registeredForNotification(batchTnftArr[i], batchTokenIdArr[i]),
                address(basket)
            );
        }

        // verify Joe balances
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, config.totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, config.newCategories);

        count = 0; // reset count
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, config.amountFingerprints);

            for (uint256 j; j < tokenIdLib.length; ++j) {
                uint256 tokenId = tokenIdMap[tnftsSupported[i]][j];
                assertEq(tokenIdLib[j], tokenId);

                assertEq(deposited[count].tnft, tnftsSupported[i]);
                assertEq(deposited[count].tokenId, tokenId);
                assertEq(deposited[count].fingerprint, j);
                ++count;
            }
        }

        // report gas metering
        emit log_named_uint("Gas Metering", gas_used);

        // reset tokenIdMap
        for (uint256 i; i < config.newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of batchDepositTNFT method using fuzzing.
    function test_stress_batchDepositTNFT_fuzzing(uint256 _categories, uint256 _fps) public {
        _categories = bound(_categories, 1, 10);
        _fps = bound(_fps, 1, 20);

        // ~ Config ~

        config.newCategories = _categories;
        config.amountFingerprints = _fps;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        uint256[] memory fingerprints = new uint256[](config.amountFingerprints);
        address[] memory tnfts = new address[](config.newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < config.amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < config.newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(batchTnftArr.length, config.totalTokens);
        assertEq(batchTokenIdArr.length, config.totalTokens);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute batchDepositTNFT ~

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        uint256 gas_start = gasleft();
        uint256[] memory shares = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);
        uint256 gas_used = gas_start - gasleft();
        vm.stopPrank();

        assertEq(shares.length, config.totalTokens);

        // ~ Post-state check ~

        // verify basket now owns token
        for (uint256 i; i < config.totalTokens; ++i) {
            assertEq(ITangibleNFT(batchTnftArr[i]).ownerOf(batchTokenIdArr[i]), address(basket));
            assertEq(basket.tokenDeposited(batchTnftArr[i], batchTokenIdArr[i]), true);

            // verify notificationDispatcher state
            assertEq(
                _getNotificationDispatcher(batchTnftArr[i]).registeredForNotification(batchTnftArr[i], batchTokenIdArr[i]),
                address(basket)
            );
        }

        // verify Joe balances
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, config.totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, config.newCategories);

        count = 0; // reset count
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, config.amountFingerprints);

            for (uint256 j; j < tokenIdLib.length; ++j) {
                uint256 tokenId = tokenIdMap[tnftsSupported[i]][j];
                assertEq(tokenIdLib[j], tokenId);

                assertEq(deposited[count].tnft, tnftsSupported[i]);
                assertEq(deposited[count].tokenId, tokenId);
                assertEq(deposited[count].fingerprint, j);
                ++count;
            }
        }

        // report gas metering
        emit log_named_uint("Gas Metering", gas_used);

        // reset tokenIdMap
        for (uint256 i; i < config.newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of batchDepositTNFT method with TNFTs accruing rent.
    /// NOTE: When num of tokens == 90, batchDepositTNFT consumes ~30.3M gas
    function test_stress_batchDepositTNFT_rent() public {
        
        // ~ Config ~
        
        config.newCategories = 3;
        config.amountFingerprints = 4;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        uint256 rent = 10_000 * WAD; // per token

        uint256[] memory fingerprints = new uint256[](config.amountFingerprints);
        address[] memory tnfts = new address[](config.newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < config.amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < config.newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < config.newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    fingerprints[j],
                    JOE
                );
                tokenIdMap[tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // deposit rent

        // deal category owner USDC to deposit into rentManager
        deal(address(DAI_MOCK), TANGIBLE_LABS, rent * config.totalTokens);

        for (uint256 i; i < tnfts.length; ++i) {
            IRentManager tempRentManager = IFactory(address(factoryV2)).rentManager(ITangibleNFT(tnfts[i]));

            for (uint256 j; j < tokenIdMap[tnfts[i]].length; ++j) {

                // deposit rent for each tnft (no vesting)
                vm.startPrank(TANGIBLE_LABS);
                DAI_MOCK.approve(address(tempRentManager), rent);
                tempRentManager.deposit(
                    tokenIdMap[tnfts[i]][j],
                    address(DAI_MOCK),
                    rent,
                    0,
                    block.timestamp + 1,
                    true
                );
                vm.stopPrank();
            }
            
        }

        skip(1); // skip to end of vesting

        // ~ Pre-state check ~

        assertEq(batchTnftArr.length, config.totalTokens);
        assertEq(batchTokenIdArr.length, config.totalTokens);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);


        // ~ Execute batchDepositTNFT ~

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }

        uint256[] memory shares = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);

        vm.stopPrank();

        assertEq(shares.length, config.totalTokens);

        // ~ Post-state check ~

        // verify basket now owns token
        for (uint256 i; i < config.totalTokens; ++i) {
            assertEq(ITangibleNFT(batchTnftArr[i]).ownerOf(batchTokenIdArr[i]), address(basket));
            assertEq(basket.tokenDeposited(batchTnftArr[i], batchTokenIdArr[i]), true);

            // verify notificationDispatcher state
            assertEq(
                _getNotificationDispatcher(batchTnftArr[i]).registeredForNotification(batchTnftArr[i], batchTokenIdArr[i]),
                address(basket)
            );
        }

        // verify rentBal
        assertEq(basket.getRentBal(), 0);
        assertEq(DAI_MOCK.balanceOf(JOE), rent * config.totalTokens);

        // verify Joe balances
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        // reset tokenIdMap
        for (uint256 i; i < config.newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }


    // ~ stress redeemTNFT ~

    /// @notice Stress test of Basket::redeemTNFT with numerous tokens -> NO RENT

    /// NOTE: 1*100   (100 tokens)   -> redeemTNFT costs 117_342 gas
    /// NOTE: 10*100  (1000 tokens)  -> redeemTNFT costs 353_157 gas
    /// NOTE: 50*100  (5000 tokens)  -> redeemTNFT costs 1_659_006 gas
    function test_stress_redeemTNFT_noFuzz() public {
        
        // ~ Config ~

        config.newCategories = 4;
        config.amountFingerprints = 5;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        uint256 i;
        for (; i < config.amountFingerprints; ++i) {
            config.fingerprints.push(i);
        }

        // create multiple tnfts.
        uint256 count;
        for (i = 0; i < config.newCategories; ++i) {
            config.tnfts.push(_deployNewTnftContract(Strings.toString(i)));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = config.tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (i = 0; i < config.newCategories; ++i) {
            address tempTnft = config.tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tempTnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tempTnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    config.fingerprints[j],
                    JOE
                );
                tokenIdMap[config.tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tempTnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tempTnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tempTnft).balanceOf(JOE), config.amountFingerprints);
        }

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (i = 0; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        uint256[] memory sharesReceived = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);

        vm.stopPrank();

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        IBasket.TokenData memory lastElement = IBasket.TokenData({
            tnft: deposited[deposited.length-1].tnft,
            tokenId: deposited[deposited.length-1].tokenId,
            fingerprint: 0
        });
        (address tnft, uint256 tokenId) = basket.nextToRedeem();
        uint256 redeemIndex = basket.indexInDepositedTnfts(tnft, tokenId);

        uint256 preTotalValue = basket.getTotalValueOfBasket();
        uint256 preValueGBP = basket.totalNftValueByCurrency("GBP");

        (, uint256 nativeValue,) = currencyCalculator.getTnftNativeValue(
            tnft,
            ITangibleNFT(tnft).tokensFingerprint(tokenId)
        );
        uint256 usdValue = currencyCalculator.getUSDValue(tnft, tokenId);

        assertEq(basket.indexInDepositedTnfts(
            lastElement.tnft, lastElement.tokenId), deposited.length-1
        );

        // ~ Execute redeem ~

        vm.prank(JOE);
        basket.redeemTNFT(sharesReceived[0], keccak256(abi.encodePacked(tnft, tokenId)));

        // ~ Post-state check ~

        emit log_named_address("Tnft address", tnft);
        emit log_named_uint("tokenId", tokenId);

        assertEq(basket.indexInDepositedTnfts(
            lastElement.tnft, lastElement.tokenId), redeemIndex
        );

        assertEq(basket.getTotalValueOfBasket(), preTotalValue - usdValue);
        assertEq(basket.totalNftValueByCurrency("GBP"), preValueGBP - nativeValue);

        assertEq(ITangibleNFT(tnft).balanceOf(address(basket)), config.amountFingerprints - 1);
        assertEq(ITangibleNFT(tnft).balanceOf(JOE), 1);

        // verify notificationDispatcher state
        assertEq(
            _getNotificationDispatcher(tnft).registeredForNotification(tnft, tokenId),
            address(0)
        );

        assertEq(basket.tokenDeposited(tnft, tokenId), false);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnft);
        assertEq(tokenIdLib.length, config.amountFingerprints - 1);

        // reset tokenIdMap
        for (i = 0; i < config.newCategories; ++i) delete tokenIdMap[config.tnfts[i]];
    }

    /// @notice Stress test of Basket::redeemTNFT with numerous tokens and random rent claimable for each token.
    /// @dev basis: 100 tokens to iterate through.

    /// NOTE: 1x100  (100 tokens)  -> redeemTNFT costs xxx gas
    /// NOTE: 4x25   (100 tokens)  -> redeemTNFT costs 117_950 gas
    /// NOTE: 10x10  (100 tokens)  -> redeemTNFT costs xxx gas
    /// NOTE: 10x100 (1000 tokens) -> redeemTNFT costs xxx gas
    function test_stress_redeemTNFT_rent_fuzzing(uint256 randomWord) public {

        // ~ Config ~

        config.newCategories = 4;
        config.amountFingerprints = 5;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        uint256 i;
        for (; i < config.amountFingerprints; ++i) {
            config.fingerprints.push(i);
        }

        // create multiple tnfts.
        uint256 count;
        for (i = 0; i < config.newCategories; ++i) {
            config.tnfts.push(_deployNewTnftContract(Strings.toString(i)));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = config.tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (i = 0; i < config.newCategories; ++i) {
            address tempTnft = config.tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tempTnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tempTnft,
                    100_000_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    config.fingerprints[j],
                    JOE
                );
                tokenIdMap[config.tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tempTnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tempTnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tempTnft).balanceOf(JOE), config.amountFingerprints);
        }

        // create rent array
        uint256 totalRent;
        for (i = 0; i < config.totalTokens; ++i) {
            config.rentArr.push((i + 1)*10**8); // $100 -> $10,000
            totalRent += config.rentArr[i];
        }

        // shuffle rent array
        for (i = 0; i < config.rentArr.length; ++i) {
            uint256 key = i + (randomWord % (config.rentArr.length - i));

            if (i != key) {
                uint256 temp = config.rentArr[key];
                config.rentArr[key] = config.rentArr[i];
                config.rentArr[i] = temp;
            }
        }

        // deal category owner USDC to deposit into rentManager
        deal(address(DAI_MOCK), TANGIBLE_LABS, totalRent);

        for (i = 0; i < config.totalTokens; ++i) {
            IRentManager tempRentManager = IFactory(address(factoryV2)).rentManager(ITangibleNFT(batchTnftArr[i]));

            // deposit rent for each tnft (no vesting)
            vm.startPrank(TANGIBLE_LABS);
            DAI_MOCK.approve(address(tempRentManager), config.rentArr[i]);
            tempRentManager.deposit(
                batchTokenIdArr[i],
                address(DAI_MOCK),
                config.rentArr[i],
                0,
                block.timestamp + 1,
                true
            );
            vm.stopPrank();
        }

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (i = 0; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        uint256[] memory sharesReceived = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);

        vm.stopPrank();

        skip(1); // skip to end of vesting

        (address tnft, uint256 tokenId) = basket.nextToRedeem();


        // ~ Execute redeemTNFT ~

        vm.prank(JOE);
        basket.redeemTNFT(sharesReceived[0], keccak256(abi.encodePacked(tnft, tokenId)));

        // ~ Post-state check 2 ~

        assertEq(ITangibleNFT(tnft).balanceOf(address(basket)), config.amountFingerprints - 1);
        assertEq(ITangibleNFT(tnft).balanceOf(JOE), 1);

        assertEq(basket.tokenDeposited(tnft, tokenId), false);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnft);
        assertEq(tokenIdLib.length, config.amountFingerprints - 1);

        emit log_named_address("Redeemed: Tnft address", tnft);
        emit log_named_uint("Redeemed: tokenId", tokenId);
        emit log_named_uint("rentArr[0]", config.rentArr[0]);

        // reset tokenIdMap
        for (i = 0; i < config.newCategories; ++i) delete tokenIdMap[config.tnfts[i]];
    }

    // ~ stress withdrawRent ~

    /// @notice This method stress tests Basket::withdrawRent
    function test_stress_withdrawRent_fuzzing(uint256 randomWord) public {

        // ~ Config ~

        config.newCategories = 4;
        config.amountFingerprints = 5;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        uint256 i;
        for (; i < config.amountFingerprints; ++i) {
            config.fingerprints.push(i);
        }

        // create multiple tnfts.
        uint256 count;
        for (i = 0; i < config.newCategories; ++i) {
            config.tnfts.push(_deployNewTnftContract(Strings.toString(i)));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = config.tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (i = 0; i < config.newCategories; ++i) {
            address tnft = config.tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    config.fingerprints[j],
                    JOE
                );
                tokenIdMap[config.tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // create rent array
        uint256 totalRent;
        for (i = 0; i < config.totalTokens; ++i) {
            config.rentArr.push((i + 1) * 10**20); // $100 -> $10,000
            totalRent += config.rentArr[i];
        }

        // shuffle rent array
        for (i = 0; i < config.rentArr.length; ++i) {
            uint256 key = i + (randomWord % (config.rentArr.length - i));

            if (i != key) {
                uint256 temp = config.rentArr[key];
                config.rentArr[key] = config.rentArr[i];
                config.rentArr[i] = temp;
            }
        }

        // deal category owner USDC to deposit into rentManager
        deal(address(DAI_MOCK), TANGIBLE_LABS, totalRent);

        for (i = 0; i < config.totalTokens; ++i) {
            IRentManager tempRentManager = IFactory(address(factoryV2)).rentManager(ITangibleNFT(batchTnftArr[i]));

            // deposit rent for each tnft (no vesting)
            vm.startPrank(TANGIBLE_LABS);
            DAI_MOCK.approve(address(tempRentManager), config.rentArr[i]);
            tempRentManager.deposit(
                batchTokenIdArr[i],
                address(DAI_MOCK),
                config.rentArr[i],
                0,
                block.timestamp + 1,
                true
            );
            vm.stopPrank();
        }

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (i = 0; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);

        vm.stopPrank();

        // skip to end of vesting
        skip(1);

        // ~ Sanity check ~

        uint256 rentBal = basket.getRentBal();

        assertGt(basket.getRentBal(), 0);
        assertEq(basket.primaryRentToken().balanceOf(factoryOwner), 0);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), 0);

        // ~ Rebase ~

        vm.prank(REBASE_INDEX_MANAGER);
        basket.rebase();
        
        // ~ Pre-state check ~

        uint256 withdrawable = rentBal - ((rentBal * basket.rentFee()) / 100_00);

        assertEq(basket.getRentBal(), withdrawable);
        assertEq(basket.totalRentValue(), withdrawable);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()), (rentBal * basket.rentFee()) / 100_00);
        assertEq(basket.primaryRentToken().balanceOf(basketManager.revenueDistributor()) + basket.totalRentValue(), rentBal);

        // ~ Execute withdrawRent ~

        vm.prank(factoryOwner);
        basket.withdrawRent(withdrawable);

        // ~ Post-state check 2 ~

        assertEq(basket.getRentBal(), 0);
        assertEq(basket.primaryRentToken().balanceOf(factoryOwner), withdrawable);

        // reset tokenIdMap
        for (i = 0; i < config.newCategories; ++i) delete tokenIdMap[config.tnfts[i]];
    }

    // ~ stress rebasing ~

    /// @notice Verifies proper state changes during rebase
    function test_stress_rebase() public {

        // ~ Config ~

        uint256 howMany = 5;
        uint256 amountRent = 10_000 * WAD;

        for (uint256 i; i < howMany; ++i) {
            // create token of certain value
            uint256[] memory tokenIds = _createItemAndMint(
                address(realEstateTnft),
                100_000_000, //100k gbp
                1,
                1,
                i, // fingerprint
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

            // ~ Pre-state check ~

            uint256 increaseRatio = (amountRent * 1e18) / basket.getTotalValueOfBasket();
            emit log_named_uint("% increase post-rebase", increaseRatio);

            uint256 preTotalValue = basket.getTotalValueOfBasket();
            uint256 preTotalSupply = basket.totalSupply();

            assertEq(preTotalSupply, basket.balanceOf(ALICE));

            // ~ rebase ~

            vm.prank(REBASE_INDEX_MANAGER);
            basket.rebase();

            // ~ Post-state check ~

            // uint256 rentPostFee = amountRent - ((amountRent * basket.rentFee()) / 100_00);
            // uint256 postRebaseSupply = preTotalSupply + ((preTotalSupply * rentPostFee) / preTotalValue);

            assertEq(basket.totalSupply(), basket.balanceOf(ALICE));
            assertGt(basket.totalSupply(), preTotalSupply);
            assertGt(basket.getTotalValueOfBasket(), preTotalValue);
            // assertWithinDiff(
            //     basket.totalSupply(),
            //     //preTotalSupply + ((preTotalSupply * increaseRatio) / 100_0000000000000000),
            //     //preTotalSupply + ((preTotalSupply * amountRent * 1e18) / (preTotalValue * 100_00)),
            //     postRebaseSupply,
            //     1e24
            // );
            assertEq(basket.getRentBal(), basket.totalRentValue());
        }
    }

    /// @notice This stress test uses fuzzing to create random entries and therefore generate random redeemables.
    function test_stress_fulfillRandomSeed_fuzzing(uint256 randomWord) public {
        randomWord = bound(randomWord, 1000, type(uint256).max);

        // ~ Config ~

        config.newCategories = 2;
        config.amountFingerprints = 10;
        config.totalTokens = config.newCategories * config.amountFingerprints;

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](config.totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](config.totalTokens);

        // store all new fingerprints in array.
        uint256 i;
        for (; i < config.amountFingerprints; ++i) {
            config.fingerprints.push(i);
        }

        // create multiple tnfts.
        uint256 count;
        for (i = 0; i < config.newCategories; ++i) {
            config.tnfts.push(_deployNewTnftContract(Strings.toString(i)));
            
            // initialize batchTnftArr
            for (uint256 j; j < config.amountFingerprints; ++j) {
                batchTnftArr[count] = config.tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (i = 0; i < config.newCategories; ++i) {
            address tnft = config.tnfts[i];
            for (uint256 j; j < config.amountFingerprints; ++j) {
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);

                uint256[] memory tokenIds = _createItemAndMint(
                    tnft,
                    100_000, // 100 GBP
                    1,       // stock
                    1,       // mint
                    config.fingerprints[j],
                    JOE
                );
                tokenIdMap[config.tnfts[i]].push(tokenIds[0]);

                // initialize batchTokenIdArr
                batchTokenIdArr[count] = tokenIds[0];
                ++count;

                assertEq(ITangibleNFT(tnft).ownerOf(tokenIds[0]), JOE);
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal + 1);
            }
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), config.amountFingerprints);
        }

        // create rent array
        uint256 totalRent;
        for (i = 0; i < config.totalTokens; ++i) {
            config.rentArr.push((i + 1)*10**8); // $100 -> $10,000
            totalRent += config.rentArr[i];
        }

        // shuffle rent array
        for (i = 0; i < config.rentArr.length; ++i) {
            uint256 key = i + (randomWord % (config.rentArr.length - i));

            if (i != key) {
                uint256 temp = config.rentArr[key];
                config.rentArr[key] = config.rentArr[i];
                config.rentArr[i] = temp;
            }
        }

        // deal category owner USDC to deposit into rentManager
        deal(address(DAI_MOCK), TANGIBLE_LABS, totalRent);

        for (i = 0; i < config.totalTokens; ++i) {
            IRentManager tempRentManager = IFactory(address(factoryV2)).rentManager(ITangibleNFT(batchTnftArr[i]));

            // deposit rent for each tnft (no vesting)
            vm.startPrank(TANGIBLE_LABS);
            DAI_MOCK.approve(address(tempRentManager), config.rentArr[i]);
            tempRentManager.deposit(
                batchTokenIdArr[i],
                address(DAI_MOCK),
                config.rentArr[i],
                0,
                block.timestamp + 1,
                true
            );
            vm.stopPrank();
        }

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (i = 0; i < config.totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);

        vm.stopPrank();

        skip(1); // skip to end of vesting

        // ~ Admin calls for random seed ~

        vm.prank(factoryOwner);
        uint256 requestId = basket.sendRequestForSeed();

        // ~ Post-state check 1 ~

        assertEq(basket.seedRequestInFlight(), true);
        assertEq(basket.pendingSeedRequestId(), requestId);
        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.requestPending(requestId), true);

        // ~ Basket receives callback ~

        _mockVrfCoordinatorResponse(address(basket), randomWord);

        (address predictedTnft, uint256 predictedTokenId) = basket.nextToRedeem();
        emit log_named_address("TNFT chosen for redeem", predictedTnft);
        emit log_named_uint("TokenId chosen for redeem", predictedTokenId);

        // ~ Post-state check 2 ~

        assertEq(basket.seedRequestInFlight(), false);
        assertEq(basket.pendingSeedRequestId(), 0);
        assertEq(basketVrfConsumer.requestTracker(requestId), address(0));
        assertEq(basketVrfConsumer.requestPending(requestId), false);

        // ~ Execute redeemTNFT ~

        vm.startPrank(JOE);
        basket.redeemTNFT(basket.balanceOf(JOE), keccak256(abi.encodePacked(predictedTnft, predictedTokenId)));
        vm.stopPrank();

        // ~ Post-state check 3 ~

        // verify new request for entropy was created
        assertEq(basket.seedRequestInFlight(), true);
        assertEq(basket.pendingSeedRequestId(), requestId + 1);
        assertEq(basketVrfConsumer.requestTracker(requestId + 1), address(basket));
        assertEq(basketVrfConsumer.requestPending(requestId + 1), true);

        assertEq(ITangibleNFT(predictedTnft).balanceOf(address(basket)), config.amountFingerprints - 1);
        assertEq(ITangibleNFT(predictedTnft).balanceOf(JOE), 1);

        assertEq(basket.tokenDeposited(predictedTnft, predictedTokenId), false);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(predictedTnft);
        assertEq(tokenIdLib.length, config.amountFingerprints - 1);

        emit log_named_address("Redeemed: Tnft address", predictedTnft);
        emit log_named_uint("Redeemed: TokenId", predictedTokenId);
        emit log_named_uint("rentArr[0]", config.rentArr[0]);

        // reset tokenIdMap
        for (i = 0; i < config.newCategories; ++i) delete tokenIdMap[config.tnfts[i]];
    }

}