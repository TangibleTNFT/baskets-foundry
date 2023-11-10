// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// tangible contracs
import { FactoryV2 } from "@tangible/FactoryV2.sol";
import { RentManager } from "@tangible/RentManager.sol";
import { RentManagerDeployer } from "@tangible/RentManagerDeployer.sol";
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { TangiblePriceManagerV2 } from "@tangible/TangiblePriceManagerV2.sol";
import { RealtyOracleTangibleV2 } from "@tangible/priceOracles/RealtyOracleV2.sol";
import { MockMatrixOracle } from "@tangible/priceOracles/MockMatrixOracle.sol";
import { CurrencyFeedV2 } from "@tangible/helpers/CurrencyFeedV2.sol";
import { TNFTMetadata } from "@tangible/TNFTMetadata.sol";
import { TangibleNFTDeployerV2 } from "@tangible/TangibleNFTDeployerV2.sol";
import { TNFTMarketplaceV2 } from "@tangible/MarketplaceV2.sol";
import { RWAPriceNotificationDispatcher } from "@tangible/notifications/RWAPriceNotificationDispatcher.sol";

// interfaces
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";
import { IRWAPriceNotificationReceiver } from "@tangible/notifications/IRWAPriceNotificationReceiver.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// local helper imports
import "./utils/MumbaiAddresses.sol";
import "./utils/Utility.sol";

/**
 * @title RWAPriceNotificationDispatcherTest
 * @author Chase Brown
 * @notice Testing file for RWAPriceNotificationDispatcher contract.
 */
contract RWAPriceNotificationDispatcherTest is Utility, IRWAPriceNotificationReceiver {
    RentManager public rentManager;
    TransparentUpgradeableProxy public rentManagerProxy;

    RentManagerDeployer public rentManagerDeployer;
    TransparentUpgradeableProxy public rentManagerDeployerProxy;

    ProxyAdmin public proxyAdmin;

    // factory
    FactoryV2 public factory;
    TransparentUpgradeableProxy public factoryProxy;
    // real Estate Tnft
    TangibleNFTV2 public realEstateTnft;
    TransparentUpgradeableProxy public realEstateTnftProxy;
    // currency feed
    CurrencyFeedV2 public currencyFeed;
    TransparentUpgradeableProxy public currencyFeedProxy;
    // metadata
    TNFTMetadata public metadata;
    TransparentUpgradeableProxy public metadataProxy;
    // price manager
    TangiblePriceManagerV2 public priceManager;
    TransparentUpgradeableProxy public priceManagerProxy;
    // real Estate Oracle
    RealtyOracleTangibleV2 public realEstateOracle;
    TransparentUpgradeableProxy public realEstateOracleProxy;
    // mock matrix oracle
    MockMatrixOracle public mockMatrixOracle;
    // Tnft deployer
    TangibleNFTDeployerV2 public tnftDeployer;
    TransparentUpgradeableProxy public tnftDeployerProxy;
    // marketplace
    TNFTMarketplaceV2 public marketplace;
    TransparentUpgradeableProxy public marketplaceProxy;
    // notifications dispatcher
    RWAPriceNotificationDispatcher public notificationDispatcher;
    TransparentUpgradeableProxy public notificationDispatcherProxy;

    address public constant TANGIBLE_LABS = address(bytes20(bytes("Tangible labs MultiSig")));
    address public constant CATEGORY_OWNER = address(bytes20(bytes("Category Owner")));

    string public constant BASE_URI = "https://example.gateway.com/ipfs/CID";

    uint256 constant public FINGERPRINT = 2222;
    uint256 constant public TNFTTYPE = 1;

    uint256 totalContractUsdValue = 0;
    uint256 decimals = 18;

    //address public constant TANGIBLE_ORACLE = 0x7A5771eC1EdCe2AD0f2d63F7952EE10db95E66Cc;
    //address public constant TANGIBLE_ORACLE_OWNER = 0x7179B719EEd8c2C60B498d2A2d04f868fb655F22;


    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        proxyAdmin = new ProxyAdmin(address(this));

        // TODO: 
        // deploy mockMatrix for realtyOracle
        // deploy notification stuff
        // set on oracle
        

        // ~ deployment ~

        // Deploy Factory with proxy
        factory = new FactoryV2();
        factoryProxy = new TransparentUpgradeableProxy(
            address(factory),
            address(proxyAdmin),
            abi.encodeWithSelector(FactoryV2.initialize.selector,
                address(MUMBAI_USDC),
                TANGIBLE_LABS
            )
        );
        factory = FactoryV2(address(factoryProxy));

        // Deplot tnft deployer with proxy
        tnftDeployer = new TangibleNFTDeployerV2();
        tnftDeployerProxy = new TransparentUpgradeableProxy(
            address(tnftDeployer),
            address(proxyAdmin),
            abi.encodeWithSelector(TangibleNFTDeployerV2.initialize.selector,
                address(factory)
            )
        );
        tnftDeployer = TangibleNFTDeployerV2(address(tnftDeployerProxy));

        // Deploy Marketplace with proxy
        marketplace = new TNFTMarketplaceV2();
        marketplaceProxy = new TransparentUpgradeableProxy(
            address(marketplace),
            address(proxyAdmin),
            abi.encodeWithSelector(TNFTMarketplaceV2.initialize.selector,
                address(factory)
            )
        );
        marketplace = TNFTMarketplaceV2(address(marketplaceProxy));

        // Deploy Currency Feed
        currencyFeed = new CurrencyFeedV2();
        currencyFeedProxy = new TransparentUpgradeableProxy(
            address(currencyFeed),
            address(proxyAdmin),
            abi.encodeWithSelector(CurrencyFeedV2.initialize.selector,
                address(factory)
            )
        );
        currencyFeed = CurrencyFeedV2(address(currencyFeedProxy));

        // Deploy Price Manager with proxy
        priceManager = new TangiblePriceManagerV2();
        priceManagerProxy = new TransparentUpgradeableProxy(
            address(priceManager),
            address(proxyAdmin),
            abi.encodeWithSelector(TangiblePriceManagerV2.initialize.selector,
                address(factory)
            )
        );
        priceManager = TangiblePriceManagerV2(address(priceManagerProxy));

        // Deploy mock matrix oracle
        mockMatrixOracle = new MockMatrixOracle();

        // Deploy Real Estate Oracle with proxy
        realEstateOracle = new RealtyOracleTangibleV2();
        realEstateOracleProxy = new TransparentUpgradeableProxy(
            address(realEstateOracle),
            address(proxyAdmin),
            abi.encodeWithSelector(RealtyOracleTangibleV2.initialize.selector,
                address(factory),
                address(currencyFeed),
                address(mockMatrixOracle)
            )
        );
        realEstateOracle = RealtyOracleTangibleV2(address(realEstateOracleProxy));

        // Deploy TNFT Metadata with proxy
        metadata = new TNFTMetadata();
        metadataProxy = new TransparentUpgradeableProxy(
            address(metadata),
            address(proxyAdmin),
            abi.encodeWithSelector(TNFTMetadata.initialize.selector,
                address(factory)
            )
        );
        metadata = TNFTMetadata(address(metadataProxy));

        // Deploy rent manager deployer with proxy
        rentManagerDeployer = new RentManagerDeployer();
        rentManagerDeployerProxy = new TransparentUpgradeableProxy(
            address(rentManagerDeployer),
            address(proxyAdmin),
            abi.encodeWithSelector(RentManagerDeployer.initialize.selector,
                address(factory)
            )
        );
        rentManagerDeployer = RentManagerDeployer(address(rentManagerDeployerProxy));

        // Deploy rent manager with proxy
        rentManager = new RentManager();
        rentManagerProxy = new TransparentUpgradeableProxy(
            address(rentManager),
            address(proxyAdmin),
            abi.encodeWithSelector(RentManager.initialize.selector,
                address(rentManager),
                address(factory)
            )
        );
        rentManager = RentManager(address(rentManagerProxy));

        currencyFeed.setISOCurrencyData("GBP", 826);
        currencyFeed.setCurrencyFeed("GBP", AggregatorV3Interface(0xb24Ce57c96d27690Ae68aa77656a821d5A53b5eB));

        // set contracts on Factory
        factory.setContract(FactoryV2.FACT_ADDRESSES.LABS,                  TANGIBLE_LABS);
        factory.setContract(FactoryV2.FACT_ADDRESSES.PRICE_MANAGER,         address(priceManager));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_META,             address(metadata));
        factory.setContract(FactoryV2.FACT_ADDRESSES.MARKETPLACE,           address(marketplace));
        factory.setContract(FactoryV2.FACT_ADDRESSES.TNFT_DEPLOYER,         address(tnftDeployer));
        factory.setContract(FactoryV2.FACT_ADDRESSES.CURRENCY_FEED,         address(currencyFeed));
        factory.setContract(FactoryV2.FACT_ADDRESSES.RENT_MANAGER_DEPLOYER, address(rentManagerDeployer));

        // Add TNFTType on TNFTMetadata contract
        metadata.addTNFTType(
            TNFTTYPE,
            "RealEstateType1",
            true
        );

        // Create new category with TNFTType on the Factory -> deploying TangibleNFT contract
        vm.prank(TANGIBLE_LABS);
        ITangibleNFT tnft = factory.newCategory(
            "TangibleREstate",
            "RLTY",
            BASE_URI,
            false,
            false,
            address(realEstateOracle),
            false,
            TNFTTYPE
        );
        realEstateTnft = TangibleNFTV2(address(tnft));

        // Deploy new notifications Dispenser
        notificationDispatcher = new RWAPriceNotificationDispatcher();
        notificationDispatcherProxy = new TransparentUpgradeableProxy(
            address(notificationDispatcher),
            address(proxyAdmin),
            abi.encodeWithSelector(RWAPriceNotificationDispatcher.initialize.selector,
                address(factory),
                address(realEstateTnft)
            )
        );
        notificationDispatcher = RWAPriceNotificationDispatcher(address(notificationDispatcherProxy));

        // set notification dispatcher on RE oracle
        vm.prank(TANGIBLE_LABS);
        realEstateOracle.setNotificationDispatcher(address(notificationDispatcher));

        mockMatrixOracle.setTangibleWrapperAddress(address(realEstateOracle));

        IRentManager rm = factory.rentManager(tnft);
        rentManager = RentManager(address(rm));

        vm.prank(TANGIBLE_LABS);
        rentManager.updateDepositor(CATEGORY_OWNER);

        // labels
        vm.label(address(factory), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(mockMatrixOracle), "MOCK_MATRIX_ORACLE");
        vm.label(CATEGORY_OWNER, "CATEGORY OWNER");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(JOE, "JOE");

    }


    // -------
    // Utility
    // -------

    /// @notice IRWAPriceNotificationReceiver::notify -> ALlows this contract to get notified of a price change
    function notify(
        address, // tnft,
        uint256, // tokenId,
        uint256, // fingeprint
        uint256 oldNativePrice,
        uint256 newNativePrice,
        uint16 currency
    ) external {

        uint256 oldNativePriceUsd = _convertToUsd(oldNativePrice, currency);
        uint256 newNativePriceUsd = _convertToUsd(newNativePrice, currency);
        
        totalContractUsdValue = (totalContractUsdValue - oldNativePriceUsd) + newNativePriceUsd;
    }

    /// @notice Helper method for converting an amount in one currency to USD.
    function _convertToUsd(uint256 value, uint16 currency) internal view returns (uint256 usdValue) {
        uint256 oracleDecimals = realEstateOracle.decimals();
        //uint256 targetDecimals = decimals - oracleDecimals;

        string memory currencyStr = currencyFeed.ISOcurrencyNumToCode(currency);
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currencyStr);
        uint256 priceDecimals = priceFeed.decimals();

        // from the price feed contract, fetch most recent exchange rate of native currency / USD
        (, int256 price, , , ) = priceFeed.latestRoundData();

        usdValue = (uint(price) * value * 10 ** 18) / 10 ** priceDecimals / 10 ** oracleDecimals;
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

    /// @notice Allows address(this) to receive ERC721 tokens.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Helper function for creating items and minting to a designated address.
    function _createItemAndMint(address tnft, uint256 _sellAt, uint256 _stock, uint256 _mintCount, uint256 _fingerprint, address _receiver) internal returns (uint256[] memory) {
        require(_mintCount >= _stock, "mint count must be gt stock");

        // create new item with fingerprint.
        mockMatrixOracle.createItem(
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
        uint256[] memory tokenIds = factory.mint(voucher);
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

    /// @notice Initial state test.
    function test_notifications_init_state() public {
        // a. verify realEstateTnft oracle
        assertEq(address(priceManager.oracleForCategory(ITangibleNFT(realEstateTnft))), address(realEstateOracle));
        // b. verufy oracle's wrapper to mockMatrix
        assertEq(address(realEstateOracle.chainlinkRWAOracle()), address(mockMatrixOracle));
        // c. verify oracle's notification dispenser
        assertEq(address(realEstateOracle.notificationDispatcher()), address(notificationDispatcher));
    }

    
    // ----------
    // Unit Tests
    // ----------

    /// @notice Verifies correct state changes when registerForNotification or unregisterForNotification is executed
    function test_notifications_registerForNotification() public {
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), false);

        // ~ Config ~

        uint256[] memory tokenIds = new uint256[](1);

        // create and mint new TNFT to this contract
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000,
            1,
            1,
            FINGERPRINT,
            address(this)
        );

        uint256 tokenId = tokenIds[0];

        vm.prank(TANGIBLE_LABS);
        notificationDispatcher.whitelistAddressAndReceiver(address(this));

        // ~ Pre-state check ~

        assertEq(realEstateTnft.ownerOf(tokenId), address(this));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(0));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);

        // ~ Execute registerForNotification ~

        notificationDispatcher.registerForNotification(tokenId);

        // ~ Post-state check 1 ~

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(this));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);

        // ~ Execute unregisterForNotification ~

        notificationDispatcher.unregisterForNotification(tokenId);

        // ~ Post-state check 2 ~

        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(0));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);
    }

    /// @notice Verifies correct execution of RWAPriceNotificationDispatcher::notify
    /// @dev uses vm.prank to trigger instead of call from oracle
    function test_notifications_notify_prank() public {

        // ~ Config ~

        uint256[] memory tokenIds = new uint256[](1);
        uint256 newPrice = 250_000_000;

        // create and mint new TNFT to this contract
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000,
            1,
            1,
            FINGERPRINT,
            address(this)
        );

        uint256 tokenId = tokenIds[0];
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);

        totalContractUsdValue += usdValue;

        vm.prank(TANGIBLE_LABS);
        notificationDispatcher.whitelistAddressAndReceiver(address(this));
        notificationDispatcher.registerForNotification(tokenId);

        // ~ Pre-state check ~

        assertEq(realEstateTnft.ownerOf(tokenId), address(this));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(this));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);
        assertEq(totalContractUsdValue, usdValue);

        // ~ Execute notify with prank ~

        vm.prank(address(realEstateOracle));
        notificationDispatcher.notify(FINGERPRINT, 100_000_000, newPrice, 826);

        // ~ Post-state check ~

        assertEq(realEstateTnft.ownerOf(tokenId), address(this));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(this));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);
        assertEq(totalContractUsdValue, _convertToUsd(newPrice, 826));
    }

    /// @notice Verifies correct execution of RWAPriceNotificationDispatcher::notify
    function test_notifications_notify_fromOracle() public {

        // ~ Config ~

        uint256[] memory tokenIds = new uint256[](1);
        uint256 newPrice = 250_000_000;

        // create and mint new TNFT to this contract
        tokenIds = _createItemAndMint(
            address(realEstateTnft),
            100_000_000,
            1,
            1,
            FINGERPRINT,
            address(this)
        );

        uint256 tokenId = tokenIds[0];
        uint256 usdValue = _getUsdValueOfNft(address(realEstateTnft), tokenId);

        totalContractUsdValue += usdValue;

        vm.prank(TANGIBLE_LABS);
        notificationDispatcher.whitelistAddressAndReceiver(address(this));
        notificationDispatcher.registerForNotification(tokenId);

        // ~ Pre-state check ~

        assertEq(realEstateTnft.ownerOf(tokenId), address(this));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(this));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);
        assertEq(totalContractUsdValue, usdValue);

        (uint256 fingerprint, uint256 weSellAt,,, uint16 currency,,) = mockMatrixOracle.fingerprintData(FINGERPRINT);
        assertEq(fingerprint, FINGERPRINT);
        assertEq(weSellAt,    100_000_000);
        assertEq(currency,    826);

        // ~ Execute notify with prank ~

        mockMatrixOracle.updateItem(FINGERPRINT, 250_000_000, 0);

        // ~ Post-state check ~

        assertEq(realEstateTnft.ownerOf(tokenId), address(this));
        assertEq(notificationDispatcher.registeredForNotification(address(realEstateTnft), tokenId), address(this));
        assertEq(notificationDispatcher.whitelistedReceiver(address(this)), true);
        assertEq(totalContractUsdValue, _convertToUsd(newPrice, 826));

        (fingerprint, weSellAt,,, currency,,) = mockMatrixOracle.fingerprintData(FINGERPRINT);
        assertEq(fingerprint, FINGERPRINT);
        assertEq(weSellAt,    250_000_000);
        assertEq(currency,    826);

    }
    
  
}