// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "../lib/forge-std/src/Test.sol";
import { StdInvariant } from "../lib/forge-std/src/StdInvariant.sol";

// oz imports
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
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

// tangible contract imports
import { FactoryProvider } from "@tangible/FactoryProvider.sol";
import { FactoryV2 } from "@tangible/FactoryV2.sol";

// tangible interface imports
import { TangibleNFTV2 } from "@tangible/TangibleNFTV2.sol";
import { IVoucher } from "@tangible/interfaces/IVoucher.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";
import { IMarketplace } from "@tangible/interfaces/IMarketplace.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IRentManager } from "@tangible/interfaces/IRentManager.sol";

// chainlink interface imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 * @title StressTests
 * @author Chase Brown
 * @notice This test file is for "stress" testing. Advanced testing methods and integration tests combined to identify
 *         the stability of the baskets protocol.
 * @dev This testing file takes advantage of Foundry's advanced testing tools: Fuzzing and Invariant testing.
 */
contract StressTests is Utility {

    // ~ Contracts ~

    // baskets
    Basket public basket;
    BasketManager public basketManager;
    BasketsVrfConsumer public basketVrfConsumer;

    // helper
    VRFCoordinatorV2Mock public vrfCoordinatorMock;

    // imported mumbai tangible contracts
    IFactory public factoryV2 = IFactory(Mumbai_FactoryV2);
    ITangibleNFT public realEstateTnft = ITangibleNFT(Mumbai_TangibleREstateTnft);
    IPriceOracle public realEstateOracle = IPriceOracle(Mumbai_RealtyOracleTangibleV2);
    IChainlinkRWAOracle public chainlinkRWAOracle = IChainlinkRWAOracle(Mumbai_MockMatrix);
    IMarketplace public marketplace = IMarketplace(Mumbai_Marketplace);
    IFactoryProvider public factoryProvider = IFactoryProvider(Mumbai_FactoryProvider);
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

    mapping(address => uint256[]) internal tokenIdMap;

    // State variables for VRF.
    uint64 internal subId;


    /// @notice Unit test config method
    function setUp() public {

        vm.createSelectFork(MUMBAI_RPC_URL);

        factoryOwner = IOwnable(address(factoryV2)).contractOwner();
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
                address(factoryProvider)
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
                address(factoryProvider),
                subId,
                address(vrfCoordinatorMock),
                MUMBAI_VRF_KEY_HASH
            )
        );
        basketVrfConsumer = BasketsVrfConsumer(address(basketVrfConsumerProxy));

        vm.prank(factoryOwner);
        basketManager.setBasketsVrfConsumer(address(basketVrfConsumer));

        vrfCoordinatorMock.addConsumer(subId, address(basketVrfConsumer));

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


        uint256[] memory tokenIds = _mintToken(address(realEstateTnft), 1, RE_FINGERPRINT_1, CREATOR);

        // Deploy basket
        uint256[] memory features = new uint256[](0);
        
        vm.startPrank(CREATOR);
        realEstateTnft.approve(address(basketManager), tokenIds[0]);
        (IBasket _basket,) = basketManager.deployBasket(
            "Tangible Basket Token",
            "TBT",
            RE_TNFTTYPE,
            address(MUMBAI_USDC),
            features,
            _asSingletonArrayAddress(address(realEstateTnft)),
            _asSingletonArrayUint(tokenIds[0])
        );
        vm.stopPrank();

        emit log_named_uint("totalNftValue", basket.totalNftValue());
        emit log_named_uint("USDVAL", _getUsdValueOfNft(address(realEstateTnft), 1));

        basket = Basket(address(_basket));

        // creator redeems token to isolate tests.
        vm.startPrank(CREATOR);
        basket.redeemTNFT(address(realEstateTnft), tokenIds[0], basket.balanceOf(CREATOR));
        vm.stopPrank();

        // labels
        vm.label(address(factoryV2), "FACTORY");
        vm.label(address(realEstateTnft), "RealEstate_TNFT");
        vm.label(address(realEstateOracle), "RealEstate_ORACLE");
        vm.label(address(chainlinkRWAOracle), "CHAINLINK_ORACLE");
        vm.label(address(marketplace), "MARKETPLACE");
        vm.label(address(factoryProvider), "FACTORY_PROVIDER");
        vm.label(address(priceManager), "PRICE_MANAGER");
        vm.label(address(basket), "BASKET");
        vm.label(address(currencyFeed), "CURRENCY_FEED");
        vm.label(address(vrfCoordinatorMock), "MOCK_VRF_COORDINATOR");
        vm.label(address(basketVrfConsumer), "BASKET_VRF_CONSUMER");
        vm.label(JOE, "JOE");
        vm.label(NIK, "NIK");
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");

        // init state check
        assertEq(basket.totalSupply(), 0);
    }


    // -------
    // Utility
    // -------

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

    /// @notice helper function for adding new categories and deploying new TNFT addresses.
    function _deployNewTnftContract(string memory name) internal returns (address) {

        // Deploy TangibleNFTV2 -> for real estate
        vm.prank(TANGIBLE_LABS);
        ITangibleNFT tnft = IFactoryExt(address(factoryV2)).newCategory(
            name,  // Name
            "RLTY",     // Symbol
            "",         // Metadata base uri
            false,      // storage price fixed
            false,      // storage required
            address(realEstateOracle), // oracle address
            false,      // symbol in uri
            RE_TNFTTYPE    // tnft type
        );

        return address(tnft);
    }

    /// @notice This method runs through the same USDValue logic as the Basket::depositTNFT
    function _getUsdValueOfNft(address _tnft, uint256 _tokenId) internal view returns (uint256 usdValue) {
        
        // ~ get Tnft Native Value ~
        
        // fetch fingerprint of product/property
        uint256 fingerprint = ITangibleNFT(_tnft).tokensFingerprint(_tokenId);
        // using fingerprint, fetch the value of the property in it's respective currency
        (uint256 value, uint256 currencyNum) = realEstateOracle.marketPriceNativeCurrency(fingerprint);
        // Fetch the string ISO code for currency
        string memory currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));
        // get decimal representation of property value
        uint256 oracleDecimals = realEstateOracle.decimals();
        
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


    // ------------
    // Stress Tests
    // ------------


    // TODO:
    // a. deposit testing with multiple TNFT addresses and multiple tokens for each TNFT contract
    //    - test deposit and batch deposits with fuzzing - DONE
    //    - again, but with rent accruing -> changing share price - DONE
    // b. stress test fulfillRandomRedeem
    //    - 1000+ depositedTnfts
    //    - tokensInBudget.length == depositedTnfts.length when > 1000 or smaller
    // c. stress test _redeemRent
    //    - 10-100+ tnftsSupported
    //    - refactor iterating thru claimable rent array and test multiple iterations with 100-1000+ TNFTs
    // d. multiple baskets


    // ~ stress depositTNFT ~

    /// @notice Stress test of depositTNFT method.
    function test_stress_depositTNFT_single() public {
        
        // ~ Config ~

        uint256 newCategories = 4;
        uint256 amountFingerprints = 25;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
        }

        // mint multiple tokens for each contract
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
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
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
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
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < tokenIdMap[tnft].length; ++j) {

                uint256 tokenId = tokenIdMap[tnft][j];
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);
                uint256 basketPreBal = basket.balanceOf(JOE);

                // get usdValue of tnft and share price
                uint256 usdValue = _getUsdValueOfNft(tnft, tokenId);
                uint256 sharePrice = basket.getSharePrice();

                // Joe executed depositTNFT
                vm.startPrank(JOE);
                ITangibleNFT(address(tnft)).approve(address(basket), tokenId);
                basket.depositTNFT(address(tnft), tokenId);
                vm.stopPrank();

                // verify share price * balance == totalValueOfBasket
                assertEq(
                    (basket.balanceOf(JOE) * sharePrice) / 1 ether,
                    basket.getTotalValueOfBasket()
                );

                // verify basket now owns token
                assertEq(ITangibleNFT(tnft).ownerOf(tokenId), address(basket));
                assertEq(basket.tokenDeposited(tnft, tokenId), true);

                // verify Joe balances
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal - 1);
                assertEq(basket.balanceOf(JOE), basketPreBal + usdValue);
                assertEq(basket.totalSupply(), basket.balanceOf(JOE));
            }
        }

        // ~ Post-state check ~

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, newCategories);

        uint256 count;
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, amountFingerprints);

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
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of depositTNFT method using fuzzing.
    function test_stress_depositTNFT_fuzzing(uint256 _categories, uint256 _fps) public {
        _categories = bound(_categories, 1, 10);
        _fps = bound(_fps, 1, 20);

        // ~ Config ~

        uint256 newCategories = _categories;
        uint256 amountFingerprints = _fps;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
        }

        // mint multiple tokens for each contract
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
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
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
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
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < tokenIdMap[tnft].length; ++j) {

                uint256 tokenId = tokenIdMap[tnft][j];
                uint256 preBal = ITangibleNFT(tnft).balanceOf(JOE);
                uint256 basketPreBal = basket.balanceOf(JOE);

                // get usdValue of tnft and share price
                uint256 usdValue = _getUsdValueOfNft(tnft, tokenId);
                uint256 sharePrice = basket.getSharePrice();

                // Joe executed depositTNFT
                vm.startPrank(JOE);
                ITangibleNFT(address(tnft)).approve(address(basket), tokenId);
                basket.depositTNFT(address(tnft), tokenId);
                vm.stopPrank();

                // verify share price * balance == totalValueOfBasket
                assertEq(
                    (basket.balanceOf(JOE) * sharePrice) / 1 ether,
                    basket.getTotalValueOfBasket()
                );

                // verify basket now owns token
                assertEq(ITangibleNFT(tnft).ownerOf(tokenId), address(basket));
                assertEq(basket.tokenDeposited(tnft, tokenId), true);

                // verify Joe balances
                assertEq(ITangibleNFT(tnft).balanceOf(JOE), preBal - 1);
                assertEq(basket.balanceOf(JOE), basketPreBal + usdValue);
                assertEq(basket.totalSupply(), basket.balanceOf(JOE));
            }
        }

        // ~ Post-state check ~

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, newCategories);

        uint256 count;
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, amountFingerprints);

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
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }


    // ~ stress batchDepositTNFT ~

    /// @notice Stress test of batchDepositTNFT method.
    /// NOTE: When num of tokens == 100, batchDepositTNFT consumes ~29.2M gas
    function test_stress_batchDepositTNFT() public {
        
        // ~ Config ~

        uint256 newCategories = 10;
        uint256 amountFingerprints = 10;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
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
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(batchTnftArr.length, totalTokens);
        assertEq(batchTokenIdArr.length, totalTokens);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute batchDepositTNFT ~

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        uint256 gas_start = gasleft();
        uint256[] memory shares = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);
        uint256 gas_used = gas_start - gasleft();
        vm.stopPrank();

        assertEq(shares.length, totalTokens);

        // ~ Post-state check ~

        // verify basket now owns token
        for (uint256 i; i < totalTokens; ++i) {
            assertEq(ITangibleNFT(batchTnftArr[i]).ownerOf(batchTokenIdArr[i]), address(basket));
            assertEq(basket.tokenDeposited(batchTnftArr[i], batchTokenIdArr[i]), true);
        }

        // verify Joe balances
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, newCategories);

        count = 0; // reset count
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, amountFingerprints);

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
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of batchDepositTNFT method using fuzzing.
    function test_stress_batchDepositTNFT_fuzzing(uint256 _categories, uint256 _fps) public {
        _categories = bound(_categories, 1, 10);
        _fps = bound(_fps, 1, 20);

        // ~ Config ~

        uint256 newCategories = _categories;
        uint256 amountFingerprints = _fps;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
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
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
        }

        // ~ Pre-state check ~

        assertEq(batchTnftArr.length, totalTokens);
        assertEq(batchTokenIdArr.length, totalTokens);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);

        Basket.TokenData[] memory deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, 0);

        address[] memory tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, 0);

        // ~ Execute batchDepositTNFT ~

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        uint256 gas_start = gasleft();
        uint256[] memory shares = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);
        uint256 gas_used = gas_start - gasleft();
        vm.stopPrank();

        assertEq(shares.length, totalTokens);

        // ~ Post-state check ~

        // verify basket now owns token
        for (uint256 i; i < totalTokens; ++i) {
            assertEq(ITangibleNFT(batchTnftArr[i]).ownerOf(batchTokenIdArr[i]), address(basket));
            assertEq(basket.tokenDeposited(batchTnftArr[i], batchTokenIdArr[i]), true);
        }

        // verify Joe balances
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        deposited = basket.getDepositedTnfts();
        assertEq(deposited.length, totalTokens);

        tnftsSupported = basket.getTnftsSupported();
        assertEq(tnftsSupported.length, newCategories);

        count = 0; // reset count
        for (uint256 i; i < tnftsSupported.length; ++i) {
            assertEq(tnftsSupported[i], tnfts[i]);

            uint256[] memory tokenIdLib = basket.getTokenIdLibrary(tnftsSupported[i]);
            assertEq(tokenIdLib.length, amountFingerprints);

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
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }

    /// @notice Stress test of batchDepositTNFT method with TNFTs accruing rent.
    /// NOTE: When num of tokens == 90, batchDepositTNFT consumes ~30.3M gas
    function test_stress_batchDepositTNFT_rent() public {
        
        // ~ Config ~

        uint256 newCategories = 9;
        uint256 amountFingerprints = 10;
        uint256 rent = 10_000 * USD; // per token

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
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
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
        }

        // deposit rent

        // deal category owner USDC to deposit into rentManager
        deal(address(MUMBAI_USDC), TANGIBLE_LABS, rent * totalTokens);

        for (uint256 i; i < tnfts.length; ++i) {
            IRentManager tempRentManager = IFactory(address(factoryV2)).rentManager(ITangibleNFT(tnfts[i]));

            for (uint256 j; j < tokenIdMap[tnfts[i]].length; ++j) {

                // deposit rent for each tnft (no vesting)
                vm.startPrank(TANGIBLE_LABS);
                MUMBAI_USDC.approve(address(tempRentManager), rent);
                tempRentManager.deposit(
                    tokenIdMap[tnfts[i]][j],
                    address(MUMBAI_USDC),
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

        assertEq(batchTnftArr.length, totalTokens);
        assertEq(batchTokenIdArr.length, totalTokens);

        assertEq(basket.balanceOf(JOE), 0);
        assertEq(basket.totalSupply(), 0);


        // ~ Execute batchDepositTNFT ~

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }

        uint256 gas_start = gasleft();
        uint256[] memory shares = basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);
        uint256 gas_used = gas_start - gasleft();

        vm.stopPrank();

        assertEq(shares.length, totalTokens);

        // ~ Post-state check ~

        // verify basket now owns token
        for (uint256 i; i < totalTokens; ++i) {
            assertEq(ITangibleNFT(batchTnftArr[i]).ownerOf(batchTokenIdArr[i]), address(basket));
            assertEq(basket.tokenDeposited(batchTnftArr[i], batchTokenIdArr[i]), true);
        }

        // verify rentBal
        assertEq(basket.getRentBal(), rent * totalTokens * 10 ** 12);

        // verify Joe balances
        assertEq(basket.totalSupply(), basket.balanceOf(JOE));

        // report gas metering
        emit log_named_uint("Gas Metering", gas_used);

        // reset tokenIdMap
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }


    // ~ stress checkBudget ~

    /// @notice Stress test of checkBudget method with max tokensInBudget.
    /// NOTE: 1x10 (100 tokens)  -> checkBudget costs 23_442_928 gas
    /// NOTE: 4x25 (100 tokens)  -> checkBudget costs 26_967_717 gas
    /// NOTE: 10x10 (100 tokens) -> checkBudget costs 34_143_566 gas -> OVER LIMIT
    function test_stress_checkBudget() public {

        // ~ Config ~

        uint256 newCategories = 10;
        uint256 amountFingerprints = 10;

        // NOTE: Amount of TNFTs == newCategories * amountFingerprints
        uint256 totalTokens = newCategories * amountFingerprints;

        uint256[] memory fingerprints = new uint256[](amountFingerprints);
        address[] memory tnfts = new address[](newCategories);

        // declare arrays that will be used for args for batchDepositTNFT
        address[] memory batchTnftArr = new address[](totalTokens);
        uint256[] memory batchTokenIdArr = new uint256[](totalTokens);

        // store all new fingerprints in array.
        for (uint256 i; i < amountFingerprints; ++i) {
            fingerprints[i] = i;
        }

        // create multiple tnfts.
        uint256 count;
        for (uint256 i; i < newCategories; ++i) {
            tnfts[i] = _deployNewTnftContract(Strings.toString(i));
            
            // initialize batchTnftArr
            for (uint256 j; j < amountFingerprints; ++j) {
                batchTnftArr[count] = tnfts[i];
                ++count;
            }
        }

        // mint multiple tokens for each contract
        count = 0;
        for (uint256 i; i < newCategories; ++i) {
            address tnft = tnfts[i];
            for (uint256 j; j < amountFingerprints; ++j) {
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
            assertEq(ITangibleNFT(tnft).balanceOf(JOE), amountFingerprints);
        }

        uint256 usdValue = _getUsdValueOfNft(tnfts[0], tokenIdMap[tnfts[0]][0]);

        // deposit tokens via batch
        vm.startPrank(JOE);
        for (uint256 i; i < totalTokens; ++i) {
            ITangibleNFT(batchTnftArr[i]).approve(
                address(basket),
                batchTokenIdArr[i]
            );
        }
        basket.batchDepositTNFT(batchTnftArr, batchTokenIdArr);

        vm.stopPrank();

        // ~ Execute checkBudget ~

        uint256 gas_start = gasleft();
        (IBasket.RedeemData[] memory inBudget, uint256 quantity, bool valid) = basket.checkBudget(usdValue);
        uint256 gas_used = gas_start - gasleft();

        // ~ Post-state check ~

        assertEq(quantity, totalTokens);
        assertEq(inBudget.length, totalTokens);
        assertEq(valid, true);

        // report gas metering
        emit log_named_uint("Gas Metering", gas_used);

        // reset tokenIdMap
        for (uint256 i; i < newCategories; ++i) delete tokenIdMap[tnfts[i]];
    }


    // ~ stress fulfillRandomRedeem ~

    // TODO

}