// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// local contracts
import { Basket } from "../src/Basket.sol";
import { IBasket } from "../src/interfaces/IBasket.sol";
import { BasketManager } from "../src/BasketsManager.sol";
import { BasketsVrfConsumer } from "../src/BasketsVrfConsumer.sol";

import { VRFCoordinatorV2Mock } from "./utils/VRFCoordinatorV2Mock.sol";
import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

// tangible contract
import { FactoryV2 } from "@tangible/FactoryV2.sol";

// tangible interface imports
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";
import { IMarketplace } from "@tangible/interfaces/IMarketplace.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 * @title MumbaiBasketsTest
 * @author Chase Brown
 * @notice This test file contains integration tests for the baskets protocol. We import real mumbai addresses of the underlying layer
 *         of smart contracts via MumbaiAddresses.sol.
 */
contract MumbaiBasketsTest is Utility {

    // ~ Contracts ~

    // baskets
    Basket public basket;
    BasketManager public basketManager;
    BasketsVrfConsumer public basketVrfConsumer;

    // helper
    VRFCoordinatorV2Mock public vrfCoordinatorMock;

    // tangible mumbai contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    ITangiblePriceManager public priceManager = ITangiblePriceManager(Mumbai_PriceManager);
    ICurrencyFeedV2 public currencyFeed = ICurrencyFeedV2(Mumbai_CurrencyFeedV2);
    ITNFTMetadata public metadata = ITNFTMetadata(Mumbai_TNFTMetadata);
    IRentManager public rentManager = IRentManager(Mumbai_RentManagerTnft);

    // proxies
    TransparentUpgradeableProxy public basketManagerProxy;
    TransparentUpgradeableProxy public basketVrfConsumerProxy;
    ProxyAdmin public proxyAdmin;

    // ~ Actors and Variables ~

    address public factoryOwner;
    address public ORACLE_OWNER = 0xf7032d3874557fAF9D9E861E5027300ABA1f0026;
    address public constant TANGIBLE_LABS = 0x23bfB039Fe7fE0764b830960a9d31697D154F2E4; // NOTE: category owner

    address public rentManagerDepositor = 0x9e9D5307451D11B2a9F84d9cFD853327F2b7e0F7;

    uint256 internal portion;

    uint256 internal JOE_TOKEN_ID;
    uint256 internal NIK_TOKEN_ID;

    uint256[] internal preMintedTokens;

    // State variables for VRF.
    uint64 internal subId;


    /// @notice Config function for test cases.
    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).owner();
        proxyAdmin = new ProxyAdmin();

        // vrf config
        vrfCoordinatorMock = new VRFCoordinatorV2Mock(100000, 100000);
        subId = vrfCoordinatorMock.createSubscription();
        vrfCoordinatorMock.fundSubscription(subId, 100 ether);

        // basket stuff
        basket = new Basket();

        // Deploy basketManager
        basketManager = new BasketManager();

        // Deploy proxy for basketManager -> initialize
        basketManagerProxy = new TransparentUpgradeableProxy(
            address(basketManager),
            address(proxyAdmin),
            abi.encodeWithSelector(BasketManager.initialize.selector,
                address(basket),
                address(factoryV2)
            )
        );
        basketManager = BasketManager(address(basketManagerProxy));

        // updateDepositor for rent manager
        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(TANGIBLE_LABS);

        // set basketManager
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.BASKETS_MANAGER, address(basketManager));

        // set currencyFeed
        vm.prank(factoryOwner);
        IFactoryExt(address(factoryV2)).setContract(IFactoryExt.FACT_ADDRESSES.CURRENCY_FEED, address(currencyFeed));

        // Deploy BasketsVrfConsumer
        basketVrfConsumer = new BasketsVrfConsumer();

        // Initialize BasketsVrfConsumer with proxy
        basketVrfConsumerProxy = new TransparentUpgradeableProxy(
            address(basketVrfConsumer),
            address(proxyAdmin),
            abi.encodeWithSelector(BasketsVrfConsumer.initialize.selector,
                address(factoryV2),
                subId,
                address(vrfCoordinatorMock),
                MUMBAI_VRF_KEY_HASH
            )
        );
        basketVrfConsumer = BasketsVrfConsumer(address(basketVrfConsumerProxy));

        // add basket to basketManager
        vm.prank(factoryOwner);
        basketManager.addBasket(address(basket));

        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        vrfCoordinatorMock.addConsumer(subId, address(basketVrfConsumer));

        vm.startPrank(ORACLE_OWNER);
        // set tangibleWrapper to be real estate oracle on chainlink oracle.
        IPriceOracleExt(address(chainlinkRWAOracle)).setTangibleWrapperAddress(
            address(realEstateOracle)
        );
        // create new item with fingerprint.
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            RE_FINGERPRINT_1,  // fingerprint
            500_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
        );
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
            RE_FINGERPRINT_2,  // fingerprint
            600_000_000,     // weSellAt
            0,            // lockedAmount
            10,           // stock
            uint16(826),  // currency -> GBP ISO NUMERIC CODE
            uint16(826)   // country -> United Kingdom ISO NUMERIC CODE
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

        // create mint voucher for RE_FP_1
        IVoucher.MintVoucher memory voucher2 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_1,                       // fingerprint
            true                                    // sendToVender
        );

        // create mint voucher for RE_FP_2
        IVoucher.MintVoucher memory voucher3 = IVoucher.MintVoucher(
            ITangibleNFT(address(realEstateTnft)),  // token
            1,                                      // mintCount
            0,                                      // price -> since token is going to vendor, dont need price
            TANGIBLE_LABS,                          // vendor
            address(0),                             // buyer
            RE_FINGERPRINT_2,                       // fingerprint
            true                                    // sendToVender
        );

        //emit log_named_address("Oracle for category", address(priceManager.oracleForCategory(realEstateTnft)));

        assertEq(ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1), true);
        //emit log_named_bool("Fingerprint added:", (ITangibleNFTExt(address(realEstateTnft)).fingerprintAdded(RE_FINGERPRINT_1)));

        // mint fingerprint RE_1 and RE_2
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        vm.prank(TANGIBLE_LABS);
        preMintedTokens = factoryV2.mint(voucher1);

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
        realEstateTnft.transferFrom(TANGIBLE_LABS, CREATOR, 1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 2);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(CREATOR), 1);

        // transfer token to JOE
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, JOE, 2);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 1);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(JOE), 1);

        // transfer token to NIK
        vm.prank(TANGIBLE_LABS);
        realEstateTnft.transferFrom(TANGIBLE_LABS, NIK, 3);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(TANGIBLE_LABS), 0);
        assertEq(IERC721(address(realEstateTnft)).balanceOf(NIK), 1);

        // Deploy basket
        uint256[] memory features = new uint256[](0);
        
        vm.startPrank(CREATOR);
        realEstateTnft.approve(address(basketManager), 1);
        (IBasket _basket,) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(1)
        );
        vm.stopPrank();

        basket = Basket(address(_basket));

        // labels
        vm.label(address(factoryV2), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(chainlinkRWAOracle), "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(basket), "BASKET");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(address(vrfCoordinatorMock), "MOCK_VRF_COORDINATOR");
        vm.label(address(basketVrfConsumer), "BASKET_VRF_CONSUMER");
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
        IPriceOracleExt(address(chainlinkRWAOracle)).createItem(
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


    // ------------------
    // Initial State Test
    // ------------------

    /// @notice Initial state test. TODO: Add more asserts
    function test_baskets_mumbai_init_state() public {
        // verify realEstateTnft
        assertEq(realEstateTnft.tokensFingerprint(1), RE_FINGERPRINT_1); // 2032

        // verify factoryV2 has correct priceManager
        assertEq(address(factoryV2.priceManager()), address(priceManager));

        // verify priceManager has oracle set
        assertEq(address(IPriceManagerExt(address(priceManager)).oracleForCategory(realEstateTnft)), address(realEstateOracle));

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
    function test_baskets_mumbai_depositTNFT_single() public {
        uint256 tokenId = JOE_TOKEN_ID;
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preSupply = basket.totalSupply();

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), preSupply);
        assertEq(basket.tokenDeposited(address(realEstateTnft), tokenId), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], 1);

        // emit deposit logic 
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 sharePrice = basket.getSharePrice();

        uint256 quote = basket.getQuoteIn(address(realEstateTnft), tokenId);

        // Execute a deposit
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", sharePrice);

        // Post-state check
        assertEq(
            ((preSupply + basket.balanceOf(JOE)) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.balanceOf(JOE), quote);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), tokenId), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, tokenId);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_1);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenIdLib.length, 2);
        assertEq(tokenIdLib[0], 1);
        assertEq(tokenIdLib[1], tokenId);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_mumbai_depositTNFT_multiple() public {
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preSupply = basket.totalSupply();

        // Pre-state check
        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(NIK), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), preSupply);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), false);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        uint256[] memory tokenidLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenidLib.length, 1);
        assertEq(tokenidLib[0], 1);

        // emit deposit logic 
        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);
        uint256 sharePrice = basket.getSharePrice();

        // Joe deposits TNFT
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Nik deposits TNFT
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), NIK_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("NIK's BASKET BALANCE", basket.balanceOf(NIK));
        emit log_named_uint("SHARE PRICE", sharePrice);

        // Post-state check
        assertEq(
            ((preSupply + basket.balanceOf(JOE) + basket.balanceOf(NIK)) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(NIK), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 2);

        assertEq(basket.balanceOf(JOE), usdValue1);
        assertEq(basket.balanceOf(NIK), usdValue2);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 3);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, JOE_TOKEN_ID);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[2].tnft, address(realEstateTnft));
        assertEq(deposited[2].tokenId, NIK_TOKEN_ID);
        assertEq(deposited[2].fingerprint, RE_FINGERPRINT_2);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 1);
        assertEq(tnftsSupported[0], address(realEstateTnft));

        tokenidLib = basket.getTokenIdLibrary(tnftsSupported[0]);
        assertEq(tokenidLib.length, 3);
        assertEq(tokenidLib[0], 1);
        assertEq(tokenidLib[1], JOE_TOKEN_ID);
        assertEq(tokenidLib[2], NIK_TOKEN_ID);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::depositTNFT() is executed.
    function test_baskets_mumbai_depositTNFT_feature() public {
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
    function test_baskets_mumbai_depositTNFT_feature_multiple() public {
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
        ITNFTMetadataExt(address(metadata)).addFeatures(featuresToAdd, descriptionsToAdd);
        ITNFTMetadataExt(address(metadata)).addFeaturesForTNFTType(RE_TNFTTYPE, featuresToAdd);
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
    function test_baskets_mumbai_batchDepositTNFT() public {
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preSupply = basket.totalSupply();

        uint256 amountTNFTs = 3;

        uint256[] memory tokenIds = _mintToken(address(realEstateTnft), amountTNFTs, RE_FINGERPRINT_1, JOE);
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
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, preBalBasket);

        // emit deposit logic 
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);
        uint256 sharePrice = basket.getSharePrice();

        // Execute a batch deposit
        vm.startPrank(JOE);
        for (uint256 i; i < amountTNFTs; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        uint256[] memory shares = basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        emit log_named_uint("JOE's BASKET BALANCE", basket.balanceOf(JOE));
        emit log_named_uint("SHARE PRICE", sharePrice);

        uint256 totalShares;
        for (uint i; i < amountTNFTs; ++i) {
            totalShares += shares[i];
        }

        // Post-state check
        assertEq(
            ((preSupply + basket.balanceOf(JOE)) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + amountTNFTs);

        assertEq(basket.balanceOf(JOE), usdValue * amountTNFTs);
        assertEq(basket.balanceOf(JOE), totalShares);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(JOE));
        for (uint256 i; i < amountTNFTs; ++i) {
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
        }

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, preBalBasket + amountTNFTs);

        for (uint256 i = 1; i < deposited.length; ++i) { // skip initial token
            assertEq(deposited[i].tokenId, tokenIds[i-1]);
            assertEq(deposited[i].fingerprint, RE_FINGERPRINT_1);
        }

        // Try to call batchDepositNFT with diff size arrays -> revert
        tokenIds = new uint256[](1);
        tnfts = new address[](2);

        vm.expectRevert("Arrays not same size");
        basket.batchDepositTNFT(tnfts, tokenIds);
    }


    // ~ Redeem Testing ~

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed.
    function test_baskets_mumbai_redeemTNFT_single() public {
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preSupply = basket.totalSupply();

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 sharePrice = basket.getSharePrice();

        // Pre-state check
        assertEq(
            ((preSupply + basket.balanceOf(JOE)) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), 1), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 2);

        uint256 quote = basket.getQuoteOut(address(realEstateTnft), JOE_TOKEN_ID);
        assertEq(quote, basket.balanceOf(JOE));

        // Joe performs a redeem
        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), JOE_TOKEN_ID, basket.balanceOf(JOE));
        vm.stopPrank();

        // Post-state check
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), preSupply);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::redeemTNFT() is executed for multiple TNFTs.
    function test_baskets_mumbai_redeemTNFT_multiple() public {
        uint256 preBalBasket = realEstateTnft.balanceOf(address(basket));
        uint256 preBalJoe = realEstateTnft.balanceOf(JOE);
        uint256 preBalNik = realEstateTnft.balanceOf(NIK);
        uint256 preSupply = basket.totalSupply();

        // ~ Config ~

        // Joe deposits token
        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        // Nik deposits token
        vm.startPrank(NIK);
        realEstateTnft.approve(address(basket), NIK_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), NIK_TOKEN_ID);
        vm.stopPrank();

        uint256 usdValue1 = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 usdValue2 = _getUsdValueOfNft(address(realEstateTnft), NIK_TOKEN_ID);
        uint256 sharePrice = basket.getSharePrice();

        // ~ Pre-state check ~

        assertEq(
            ((preSupply + basket.balanceOf(JOE) + basket.balanceOf(NIK)) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe - 1);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 2);

        assertEq(basket.balanceOf(JOE), usdValue1);
        assertEq(basket.balanceOf(NIK), usdValue2);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(JOE) + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 3);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, JOE_TOKEN_ID);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[2].tnft, address(realEstateTnft));
        assertEq(deposited[2].tokenId, NIK_TOKEN_ID);
        assertEq(deposited[2].fingerprint, RE_FINGERPRINT_2);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 3);
        assertEq(tokenIdLib[0], 1);
        assertEq(tokenIdLib[1], JOE_TOKEN_ID);
        assertEq(tokenIdLib[2], NIK_TOKEN_ID);

        uint256 quote = basket.getQuoteOut(address(realEstateTnft), JOE_TOKEN_ID);
        assertEq(quote, basket.balanceOf(JOE));

        // ~ Joe performs a redeem ~

        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), JOE_TOKEN_ID, basket.balanceOf(JOE));
        vm.stopPrank();

        // ~ Post-state check 1 ~

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik - 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), usdValue2);
        assertEq(basket.totalSupply(), preSupply + basket.balanceOf(NIK));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), true);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 2);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, 1);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);
        assertEq(deposited[1].tnft, address(realEstateTnft));
        assertEq(deposited[1].tokenId, NIK_TOKEN_ID);
        assertEq(deposited[1].fingerprint, RE_FINGERPRINT_2);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 2);
        assertEq(tokenIdLib[0], 1);
        assertEq(tokenIdLib[1], NIK_TOKEN_ID);

        quote = basket.getQuoteOut(address(realEstateTnft), NIK_TOKEN_ID);
        assertEq(quote, basket.balanceOf(NIK));

        // ~ Nik performs a redeem ~

        vm.startPrank(NIK);
        basket.redeemTNFT(address(realEstateTnft), NIK_TOKEN_ID, basket.balanceOf(NIK));
        vm.stopPrank();

        // ~ Post-state check 2 ~

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(NIK), preBalNik);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.balanceOf(NIK), 0);
        assertEq(basket.totalSupply(), preSupply);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);
        assertEq(basket.tokenDeposited(address(realEstateTnft), NIK_TOKEN_ID), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
    }

    function test_baskets_mumbai_redeemTNFT_mathCheck1() public {

        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

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

        // Pre-state check
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

        // Alice executes a deposit
        vm.startPrank(ALICE);
        realEstateTnft.approve(address(basket), aliceToken);
        basket.depositTNFT(address(realEstateTnft), aliceToken); // minted `130.000000000000000000`
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
        basket.depositTNFT(address(realEstateTnft), bobToken); // minted `65.000000000000000000`
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

        uint256 quoteOut = basket.getQuoteOut(address(realEstateTnft), bobToken);
        uint256 preBalBob = basket.balanceOf(BOB);

        // TODO: Add check for share price

        // Bob executes a redeem of bobToken
        vm.startPrank(BOB);
        basket.redeemTNFT(address(realEstateTnft), bobToken, basket.balanceOf(BOB)); // burned `60.357142857142857142`
        vm.stopPrank();

        // Post-state check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 0);

        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 10 * USD);
        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 5 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        assertEq(realEstateTnft.balanceOf(ALICE), 0);
        assertEq(realEstateTnft.balanceOf(BOB), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        //assertEq(basket.balanceOf(ALICE), (100 ether * 1.30 ether) / 1 ether); // Note: Odd exchange rate math TODO: Refactor
        assertEq(basket.balanceOf(BOB), preBalBob - quoteOut);
        assertEq(basket.totalSupply(), basket.balanceOf(ALICE) + (preBalBob - quoteOut));
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, aliceToken);
        assertEq(deposited[0].fingerprint, 1);

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], aliceToken);
    }

    function test_baskets_mumbai_redeemTNFT_mathCheck2() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

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

        // Pre-state check
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

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        // Alice executes a deposit
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
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        uint256 quoteOut = basket.getQuoteOut(address(realEstateTnft), bobToken);
        uint256 preBalAlice = basket.balanceOf(ALICE);

        // TODO: Add check for share price

        // Alice executes a redeem of bobToken -> Only using half of her tokens
        vm.startPrank(ALICE);
        basket.redeemTNFT(address(realEstateTnft), bobToken, basket.balanceOf(ALICE) / 2);
        vm.stopPrank();

        // Post-state check
        assertEq(rentManager.claimableRentForToken(aliceToken), 10 * USD);
        assertEq(rentManager.claimableRentForToken(bobToken), 0);

        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 5 * USD);
        assertEq(MUMBAI_USDC.balanceOf(address(rentManager)), 10 * USD);
        assertEq(MUMBAI_USDC.balanceOf(ALICE), 0);
        assertEq(MUMBAI_USDC.balanceOf(BOB), 0);

        assertEq(realEstateTnft.balanceOf(ALICE), 1);
        assertEq(realEstateTnft.balanceOf(BOB), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(ALICE), preBalAlice - quoteOut);
        assertEq(basket.balanceOf(BOB), (50 ether * 1.30 ether) / 1 ether);
        assertEq(basket.totalSupply(), basket.balanceOf(ALICE) + basket.balanceOf(BOB));
        assertEq(basket.tokenDeposited(address(realEstateTnft), aliceToken), true);
        assertEq(basket.tokenDeposited(address(realEstateTnft), bobToken), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, aliceToken);
        assertEq(deposited[0].fingerprint, 1);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], aliceToken);
    }


    // ~ Randomized Redeem Testing (redeemRandomTNFT & fulfillRandomRedeem) ~

    /// @notice Verifies restrictions and correct state changes when Basket::redeemRandomTNFT() is executed.
    function test_baskets_mumbai_redeemRandomTNFT() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 joeBal = basket.balanceOf(JOE);
        uint256 foreshadowRequestId = 1;

        // sanity check
        assertEq(joeBal, usdValue);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);

        // Pre-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), false);
        (address redeemer, uint256 budget) = basket.redeemRequestInFlightData(foreshadowRequestId);
        assertEq(redeemer, address(0));
        assertEq(budget, 0);

        // Attempt to execute redeemRandomTNFT with more tokens than what is in balance -> revert
        vm.prank(JOE);
        vm.expectRevert("Insufficient balance");
        basket.redeemRandomTNFT(joeBal + 1);

        // Execute redeemRandomTNFT -> success
        vm.prank(JOE);
        uint256 requestId = basket.redeemRandomTNFT(joeBal);

        // Post-state check
        assertEq(foreshadowRequestId, requestId);
        assertEq(basket.redeemerHasRequestInFlight(JOE), true);
        (redeemer, budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, JOE);
        assertEq(budget, joeBal);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fulfilled(requestId), false);

        // Attempt to execute redeemRandomTNFT while Joe already has request in-flight -> revert
        vm.prank(JOE);
        vm.expectRevert("redeem request in progress");
        basket.redeemRandomTNFT(joeBal);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::fulfillRandomRedeem() is executed.
    function test_baskets_mumbai_fulfillRandomRedeem_single() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), JOE_TOKEN_ID);
        basket.depositTNFT(address(realEstateTnft), JOE_TOKEN_ID);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), JOE_TOKEN_ID);
        uint256 joeBal = basket.balanceOf(JOE);
        uint256 foreshadowRequestId = 1;

        // sanity check
        assertEq(joeBal, usdValue);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);

        // Execute redeemRandomTNFT
        vm.prank(JOE);
        uint256 requestId = basket.redeemRandomTNFT(joeBal);

        // Pre-state check
        assertEq(foreshadowRequestId, requestId);
        assertEq(basket.redeemerHasRequestInFlight(JOE), true);
        (address redeemer, uint256 budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, JOE);
        assertEq(budget, joeBal);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fulfilled(requestId), false);

        assertEq(realEstateTnft.balanceOf(JOE), 0);
        assertEq(realEstateTnft.balanceOf(address(basket)), 1);

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), true);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 1);
        assertEq(deposited[0].tnft, address(realEstateTnft));
        assertEq(deposited[0].tokenId, JOE_TOKEN_ID);
        assertEq(deposited[0].fingerprint, RE_FINGERPRINT_1);

        address[] memory supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 1);
        assertEq(supportedTnfts[0], address(realEstateTnft));

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 1);
        assertEq(tokenIdLib[0], JOE_TOKEN_ID);

        // Create randomWords
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 61178987073406078724701307170779414601596042041161032433419212917987219263374; // Random Input from real VRF response.
        // NOTE: Wont be used since array will only be of size 1.

        // Vrf coordinator executes basketsVrfConsumer::rawfulfillRandomWords which calls basket::fulfillRandomRedeem
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(requestId, randomWords);

        // Post-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), false);
        (redeemer, budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, address(0));
        assertEq(budget, 0);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(0));
        assertEq(basketVrfConsumer.fulfilled(requestId), true);

        assertEq(realEstateTnft.balanceOf(JOE), 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), 0);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);
        assertEq(basket.tokenDeposited(address(realEstateTnft), JOE_TOKEN_ID), false);

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        supportedTnfts = basket.getTnftsSupported();
        assertEq(supportedTnfts.length, 0);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, 0);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::fulfillRandomRedeem() is executed.
    /// @dev This test is used to test the predictability of the randomWord var in fulfillRandomRedeem.
    ///      We will hard code the randomWord var to select a targeted tokenId. In this case, tokenId 3 in the
    ///      tokensInBudget array.
    function test_baskets_mumbai_fulfillRandomRedeem_multiple_tokenId_4() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        uint256 batchSize = 4;
        uint256 preBal = realEstateTnft.balanceOf(JOE);
        uint256 targetedIndex = 0;

        // Mint Joe 4 TNFTs to be deposited. They will all be the same price to ensure max random possibilities
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // 100,000 GBP
            batchSize,   // stock
            batchSize,   // mintCount
            1,           // fingerprint
            JOE          // receiver
        );

        uint256 targetedTokenId = tokenIds[targetedIndex]; // 4

        address[] memory tnfts = new address[](tokenIds.length);
        for (uint i; i < tnfts.length; ++i) { tnfts[i] = address(realEstateTnft); }

        // deposit all new TNFTs via batchDepositTNFT
        vm.startPrank(JOE);
        for (uint i; i < tokenIds.length; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);

        // Execute redeemRandomTNFT
        vm.prank(JOE);
        uint256 requestId = basket.redeemRandomTNFT(usdValue);

        // Pre-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), true);
        (address redeemer, uint256 budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, JOE);
        assertEq(budget, usdValue);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fulfilled(requestId), false);

        assertEq(realEstateTnft.balanceOf(JOE), preBal);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize);

        assertEq(basket.balanceOf(JOE), usdValue * batchSize);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(deposited[i].tnft, address(realEstateTnft));
            assertEq(deposited[i].tokenId, tokenIds[i]);
            assertEq(deposited[i].fingerprint, 1);
        }

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(tokenIdLib[i], tokenIds[i]);
        }

        // Note: We will specify a random number to redeem tokenId 3
        //       tokensInBudget = [{4}, 5, 6, 7]
        //       tokensInBudget[0] = tokensInBudget[key] -> index 0 will be chosen to redeem ALWAYS
        //       key = i + (randomWord % (len - i))
        //       key = 0 + (4 % (4 - 0))
        //       key = 0 -> index 0 -> tokenId 4
        //       randomWord = 4

        // Create randomWords
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 4;

        // Vrf coordinator executes basketsVrfConsumer::rawfulfillRandomWords which calls basket::fulfillRandomRedeem
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(requestId, randomWords);

        // Post-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), false);
        (redeemer, budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, address(0));
        assertEq(budget, 0);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(0));
        assertEq(basketVrfConsumer.fulfilled(requestId), true);

        assertEq(realEstateTnft.balanceOf(JOE), preBal + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize - 1);
        assertEq(realEstateTnft.ownerOf(targetedTokenId), JOE);

        assertEq(basket.balanceOf(JOE), usdValue * (batchSize - 1));
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize - 1);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize - 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::fulfillRandomRedeem() is executed.
    /// @dev This test is used to test the predictability of the randomWord var in fulfillRandomRedeem.
    ///      We will hard code the randomWord var to select a targeted tokenId. In this case, tokenId 4 in the
    ///      tokensInBudget array.
    function test_baskets_mumbai_fulfillRandomRedeem_multiple_tokenId_5() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        uint256 batchSize = 4;
        uint256 preBal = realEstateTnft.balanceOf(JOE);
        uint256 targetedIndex = 1;

        // Mint Joe 4 TNFTs to be deposited. They will all be the same price to ensure max random possibilities
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // 100,000 GBP
            batchSize,   // stock
            batchSize,   // mintCount
            1,           // fingerprint
            JOE          // receiver
        );

        uint256 targetedTokenId = tokenIds[targetedIndex]; // 5

        address[] memory tnfts = new address[](tokenIds.length);
        for (uint i; i < tnfts.length; ++i) { tnfts[i] = address(realEstateTnft); }

        // deposit all new TNFTs via batchDepositTNFT
        vm.startPrank(JOE);
        for (uint i; i < tokenIds.length; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);

        // Execute redeemRandomTNFT
        vm.prank(JOE);
        uint256 requestId = basket.redeemRandomTNFT(usdValue);

        // Pre-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), true);
        (address redeemer, uint256 budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, JOE);
        assertEq(budget, usdValue);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fulfilled(requestId), false);

        assertEq(realEstateTnft.balanceOf(JOE), preBal);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize);

        assertEq(basket.balanceOf(JOE), usdValue * batchSize);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(deposited[i].tnft, address(realEstateTnft));
            assertEq(deposited[i].tokenId, tokenIds[i]);
            assertEq(deposited[i].fingerprint, 1);
        }

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(tokenIdLib[i], tokenIds[i]);
        }

        // Note: We will specify a random number to redeem tokenId 4
        //       tokensInBudget = [4, {5}, 6, 7]
        //       tokensInBudget[0] = tokensInBudget[key] -> index 0 will be chosen to redeem ALWAYS
        //       key = i + (randomWord % (len - i))
        //       key = 0 + (5 % (4 - 0))
        //       key = 1 -> index 1 -> tokenId 5
        //       randomWord = 5

        // Create randomWords
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 5;

        // Vrf coordinator executes basketsVrfConsumer::rawfulfillRandomWords which calls basket::fulfillRandomRedeem
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(requestId, randomWords);

        // Post-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), false);
        (redeemer, budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, address(0));
        assertEq(budget, 0);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(0));
        assertEq(basketVrfConsumer.fulfilled(requestId), true);

        assertEq(realEstateTnft.balanceOf(JOE), preBal + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize - 1);
        assertEq(realEstateTnft.ownerOf(targetedTokenId), JOE);

        assertEq(basket.balanceOf(JOE), usdValue * (batchSize - 1));
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize - 1);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize - 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::fulfillRandomRedeem() is executed.
    /// @dev This test is used to test the predictability of the randomWord var in fulfillRandomRedeem.
    ///      We will hard code the randomWord var to select a targeted tokenId. In this case, tokenId 5 in the
    ///      tokensInBudget array.
    function test_baskets_mumbai_fulfillRandomRedeem_multiple_tokenId_6() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        uint256 batchSize = 4;
        uint256 preBal = realEstateTnft.balanceOf(JOE);
        uint256 targetedIndex = 2;

        // Mint Joe 4 TNFTs to be deposited. They will all be the same price to ensure max random possibilities
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // 100,000 GBP
            batchSize,   // stock
            batchSize,   // mintCount
            1,           // fingerprint
            JOE          // receiver
        );

        uint256 targetedTokenId = tokenIds[targetedIndex]; // 6

        address[] memory tnfts = new address[](tokenIds.length);
        for (uint i; i < tnfts.length; ++i) { tnfts[i] = address(realEstateTnft); }

        // deposit all new TNFTs via batchDepositTNFT
        vm.startPrank(JOE);
        for (uint i; i < tokenIds.length; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);

        // Execute redeemRandomTNFT
        vm.prank(JOE);
        uint256 requestId = basket.redeemRandomTNFT(usdValue);

        // Pre-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), true);
        (address redeemer, uint256 budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, JOE);
        assertEq(budget, usdValue);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fulfilled(requestId), false);

        assertEq(realEstateTnft.balanceOf(JOE), preBal);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize);

        assertEq(basket.balanceOf(JOE), usdValue * batchSize);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(deposited[i].tnft, address(realEstateTnft));
            assertEq(deposited[i].tokenId, tokenIds[i]);
            assertEq(deposited[i].fingerprint, 1);
        }

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(tokenIdLib[i], tokenIds[i]);
        }

        // Note: We will specify a random number to redeem tokenId 5
        //       tokensInBudget = [4, 5, {6}, 7]
        //       tokensInBudget[0] = tokensInBudget[key] -> index 0 will be chosen to redeem ALWAYS
        //       key = i + (randomWord % (len - i))
        //       key = 0 + (6 % (4 - 0))
        //       key = 2 -> index 2 -> tokenId 6
        //       randomWord = 6

        // Create randomWords
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 6;

        // Vrf coordinator executes basketsVrfConsumer::rawfulfillRandomWords which calls basket::fulfillRandomRedeem
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(requestId, randomWords);

        // Post-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), false);
        (redeemer, budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, address(0));
        assertEq(budget, 0);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(0));
        assertEq(basketVrfConsumer.fulfilled(requestId), true);

        assertEq(realEstateTnft.balanceOf(JOE), preBal + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize - 1);
        assertEq(realEstateTnft.ownerOf(targetedTokenId), JOE);

        assertEq(basket.balanceOf(JOE), usdValue * (batchSize - 1));
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize - 1);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize - 1);
    }

    /// @notice Verifies restrictions and correct state changes when Basket::fulfillRandomRedeem() is executed.
    /// @dev This test is used to test the predictability of the randomWord var in fulfillRandomRedeem.
    ///      We will hard code the randomWord var to select a targeted tokenId. In this case, tokenId 6 in the
    ///      tokensInBudget array.
    function test_baskets_mumbai_fulfillRandomRedeem_multiple_tokenId_7() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        uint256 batchSize = 4;
        uint256 preBal = realEstateTnft.balanceOf(JOE);
        uint256 targetedIndex = 3;

        // Mint Joe 4 TNFTs to be deposited. They will all be the same price to ensure max random possibilities
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // 100,000 GBP
            batchSize,   // stock
            batchSize,   // mintCount
            1,           // fingerprint
            JOE          // receiver
        );

        uint256 targetedTokenId = tokenIds[targetedIndex]; // 7

        address[] memory tnfts = new address[](tokenIds.length);
        for (uint i; i < tnfts.length; ++i) { tnfts[i] = address(realEstateTnft); }

        // deposit all new TNFTs via batchDepositTNFT
        vm.startPrank(JOE);
        for (uint i; i < tokenIds.length; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);

        // Execute redeemRandomTNFT
        vm.prank(JOE);
        uint256 requestId = basket.redeemRandomTNFT(usdValue);

        // Pre-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), true);
        (address redeemer, uint256 budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, JOE);
        assertEq(budget, usdValue);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(basket));
        assertEq(basketVrfConsumer.fulfilled(requestId), false);

        assertEq(realEstateTnft.balanceOf(JOE), preBal);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize);

        assertEq(basket.balanceOf(JOE), usdValue * batchSize);
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(basket.tokenDeposited(address(realEstateTnft), tokenIds[i]), true);
        }

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(deposited[i].tnft, address(realEstateTnft));
            assertEq(deposited[i].tokenId, tokenIds[i]);
            assertEq(deposited[i].fingerprint, 1);
        }

        uint256[] memory tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize);
        for (uint i; i < tokenIds.length; ++i) { 
            assertEq(tokenIdLib[i], tokenIds[i]);
        }

        // Note: We will specify a random number to redeem tokenId 6
        //       tokensInBudget = [4, 5, 6, {7}]
        //       tokensInBudget[0] = tokensInBudget[key] -> index 0 will be chosen to redeem ALWAYS
        //       key = i + (randomWord % (len - i))
        //       key = 0 + (7 % (4 - 0))
        //       key = 3 -> index 3 -> tokenId 7
        //       randomWord = 7

        // Create randomWords
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 7;

        // Vrf coordinator executes basketsVrfConsumer::rawfulfillRandomWords which calls basket::fulfillRandomRedeem
        vm.prank(address(vrfCoordinatorMock));
        basketVrfConsumer.rawFulfillRandomWords(requestId, randomWords); // 625_351 gas

        // Post-state check
        assertEq(basket.redeemerHasRequestInFlight(JOE), false);
        (redeemer, budget) = basket.redeemRequestInFlightData(requestId);
        assertEq(redeemer, address(0));
        assertEq(budget, 0);

        assertEq(basketVrfConsumer.requestTracker(requestId), address(0));
        assertEq(basketVrfConsumer.fulfilled(requestId), true);

        assertEq(realEstateTnft.balanceOf(JOE), preBal + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), batchSize - 1);
        assertEq(realEstateTnft.ownerOf(targetedTokenId), JOE);

        assertEq(basket.balanceOf(JOE), usdValue * (batchSize - 1));
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, batchSize - 1);

        tokenIdLib = basket.getTokenIdLibrary(address(realEstateTnft));
        assertEq(tokenIdLib.length, batchSize - 1);
    }

    /// @notice Verifies precision calculation of shares when depositing or redeeming
    function test_baskets_mumbai_checkPrecision_noRent_fuzzing(uint256 _value) public {
        _value = bound(_value, 10, 100_000_000_000); // range (.01 -> 100M)

        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

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

        // get usd value of token
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);
        uint256 sharePrice = basket.getSharePrice();

        emit log_named_uint("Usd val of token", usdValue);

        // ~ Joe deposits ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        // state check
        assertEq(
            (basket.balanceOf(JOE) * sharePrice) / 1 ether,
            basket.getTotalValueOfBasket()
        );

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(),  usdValue);

        // ~ Joe redeems ~

        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), tokenId, basket.balanceOf(JOE));
        vm.stopPrank();

        // state check -> verify totalSup is 0. SharesRequired == total balance of actor
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(),  0);
    }

    /// @notice Verifies precision calculation of shares when depositing or redeeming
    function test_baskets_mumbai_checkPrecision_rent_fuzzing(uint256 _value, uint256 _rent) public {
        _value = bound(_value, 10, 100_000_000_000); // range (.01 -> 100M) decimals = 3
        _rent  = bound(_rent, 1, 1_000_000_000_000); // range (.000001 -> 1M) decimals = 6

        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

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
        uint256 sharePrice = basket.getSharePrice();

        emit log_named_uint("Usd val of token", usdValue);

        // ~ Joe deposits ~

        vm.startPrank(JOE);
        realEstateTnft.approve(address(basket), tokenId);
        basket.depositTNFT(address(realEstateTnft), tokenId);
        vm.stopPrank();

        

        // state check
        assertEq(
            (basket.balanceOf(JOE) * sharePrice) / 1 ether + (_rent * 10**12),
            basket.getTotalValueOfBasket()
        );

        assertEq(MUMBAI_USDC.balanceOf(address(basket)), _rent);
        assertEq(MUMBAI_USDC.balanceOf(JOE), 0);

        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket + 1);
        assertEq(realEstateTnft.ownerOf(tokenId), address(basket));

        assertEq(basket.balanceOf(JOE), usdValue);
        assertEq(basket.totalSupply(),  usdValue);

        // ~ Joe redeems ~

        vm.startPrank(JOE);
        basket.redeemTNFT(address(realEstateTnft), tokenId, basket.balanceOf(JOE));
        vm.stopPrank();

        // state check -> verify totalSup is 0. SharesRequired == total balance of actor
        assertEq(realEstateTnft.balanceOf(JOE), preBalJoe + 1);
        assertEq(realEstateTnft.balanceOf(address(basket)), preBalBasket);
        assertEq(realEstateTnft.ownerOf(tokenId), JOE);

        assertEq(MUMBAI_USDC.balanceOf(address(basket)), 0);
        assertEq(MUMBAI_USDC.balanceOf(JOE), _rent);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(),  0);
    }


    // ----------------------
    // View Method Unit Tests
    // ----------------------


    // ~ getTotalValueOfBasket ~
    // TODO: Write getTotalValueOfBasket test using fuzzing

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket
    function test_baskets_mumbai_getTotalValueOfBasket_single() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

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

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), rentClaimable * 10**12);
        assertEq(totalValue, usdValue1 + basket.getRentBal());
    }

    /// @notice Verifies getTotalValueOfBasket is returning accurate value of basket with many TNFTs.
    function test_baskets_mumbai_getTotalValueOfBasket_multiple() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

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

        // call getTotalValueOfBasket
        uint256 totalValue = basket.getTotalValueOfBasket();
        
        // post state check
        emit log_named_uint("Total value of basket", totalValue);
        assertEq(basket.getRentBal(), (rentClaimable1 * 10**12) + (rentClaimable2 * 10**12));
        assertEq(totalValue, usdValue1 + usdValue2 + basket.getRentBal());
    }


    // ~ checkBudget ~

    /// @notice Verifies checkBudget view method is returning correct data
    function test_baskets_mumbai_checkBudget() public {
        // creator redeems token to isolate test.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), 1, basket.balanceOf(CREATOR));
        vm.stopPrank();

        uint256 batchSize = 4;

        // Mint Bob 4 TNFTs to be deposited.
        uint256[] memory tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000, // 100,000 GBP
            batchSize,   // stock
            batchSize,   // mintCount
            1,           // fingerprint
            BOB          // receiver
        );

        address[] memory tnfts = new address[](tokenIds.length);
        for (uint i; i < tnfts.length; ++i) { tnfts[i] = address(realEstateTnft); }

        // deposit all new TNFTs via batchDepositTNFT
        vm.startPrank(BOB);
        for (uint i; i < tokenIds.length; ++i) {
            realEstateTnft.approve(address(basket), tokenIds[i]);
        }
        basket.batchDepositTNFT(tnfts, tokenIds);
        vm.stopPrank();

        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenIds[0]);

        // Sanity check -> Execute checkBudget(0)
        (IBasket.RedeemData[] memory inBudget, uint256 quantity, bool valid) = basket.checkBudget(0);

        assertEq(inBudget.length, batchSize);
        assertEq(inBudget[0].tnft, address(0));
        assertEq(inBudget[0].tokenId, 0);
        assertEq(inBudget[0].usdValue, 0);
        assertEq(inBudget[0].sharesRequired, 0);
        assertEq(inBudget[1].tnft, address(0));
        assertEq(inBudget[1].tokenId, 0);
        assertEq(inBudget[1].usdValue, 0);
        assertEq(inBudget[1].sharesRequired, 0);
        assertEq(inBudget[2].tnft, address(0));
        assertEq(inBudget[2].tokenId, 0);
        assertEq(inBudget[2].usdValue, 0);
        assertEq(inBudget[2].sharesRequired, 0);
        assertEq(inBudget[3].tnft, address(0));
        assertEq(inBudget[3].tokenId, 0);
        assertEq(inBudget[3].usdValue, 0);
        assertEq(inBudget[3].sharesRequired, 0);
        assertEq(quantity, 0);
        assertEq(valid, false);

        // Execute checkBudget() with Bob's basket token balance
        (inBudget, quantity, valid) = basket.checkBudget(usdValue);

        assertEq(inBudget.length, batchSize);
        assertEq(inBudget[0].tnft, address(realEstateTnft));
        assertEq(inBudget[0].tokenId, tokenIds[0]);
        assertEq(inBudget[0].usdValue, usdValue);
        assertEq(inBudget[0].sharesRequired, usdValue);
        assertEq(inBudget[1].tnft, address(realEstateTnft));
        assertEq(inBudget[1].tokenId, tokenIds[1]);
        assertEq(inBudget[1].usdValue, usdValue);
        assertEq(inBudget[1].sharesRequired, usdValue);
        assertEq(inBudget[2].tnft, address(realEstateTnft));
        assertEq(inBudget[2].tokenId, tokenIds[2]);
        assertEq(inBudget[2].usdValue, usdValue);
        assertEq(inBudget[2].sharesRequired, usdValue);
        assertEq(inBudget[3].tnft, address(realEstateTnft));
        assertEq(inBudget[3].tokenId, tokenIds[3]);
        assertEq(inBudget[3].usdValue, usdValue);
        assertEq(inBudget[3].sharesRequired, usdValue);
        assertEq(quantity, batchSize);
        assertEq(valid, true);
    }
}