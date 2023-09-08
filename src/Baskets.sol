// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { ITangibleNFT, ITangibleNFTExt } from "@tangible/interfaces/ITangibleNFT.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";

import { Owned } from "./abstract/Owned.sol";
import { IBasket } from "./IBaskets.sol";

// TODO: How to handle rent? rent is redeemed when the TNFT is redeemed
// TODO: Who is the owner of the contract? Creator or Tangible?
// TODO: How is rent sent to this contract? Time basis? What asset(s)?
// TODO: How to handle storage? Does this contract have to pay for storage? TBA
// TODO: Are there any other rewards besides rent? No
// TODO: How to handle total value? TBA

// NOTE: Make sure rev share and rent managers are updated properly
// NOTE: Test how proxy contracts can be implemented.

/**
 * @title Basket
 * @author TangibleStore
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is ERC20, FactoryModifiers, Owned {

    // ~ State Variables ~

    struct TokenData {
        address tnft;
        uint256 tokenId;
        uint256 fingerprint;
    }

    TokenData[] public depositedTnfts;

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) public tokenDeposited;

    mapping(uint256 => bool) public featureSupported;

    mapping(string => bool) public currencySupported;

    mapping(string => uint256) public currencyBalance;

    string[] public supportedCurrency; // TODO: Revisit -> https://github.com/TangibleTNFT/usdr/blob/master/contracts/TreasuryTracker.sol

    address[] public supportedRentToken;

    IERC20Metadata public primaryRentToken; // USDC by default

    ICurrencyFeedV2 public currencyFeed;

    uint256 public immutable tnftType;

    bool public activelySupportingFeature;


    // ~ Events ~

    event DepositedTNFT(address prevOwner, address indexed tnft, uint256 indexed tokenId);

    event RedeemedTNFT(address newOwner, address indexed tnft, uint256 indexed tokenId);

    event FeatureSupportAdded(uint256 feature);

    event FeatureSupportRemoved(uint256 feature);



    // ~ Constructor ~

    /**
     * @notice Initializes Basket contract. // TODO: Only a TNFT holder should be able to create basket, immediately deposits (do this in deployer)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _factoryProvider,
        uint256 _tnftType,
        address _currencyFeed,
        address _rentToken,
        uint256[] memory _features
    )
        ERC20(_name, _symbol) 
        FactoryModifiers(_factoryProvider) 
        Owned(msg.sender) 
    {
        require(_factoryProvider != address(0), "FactoryProvider == address(0)");
        // TODO: Verify msg.sender is deployer or factory owner.
        
        if (_features.length != 0) activelySupportingFeature = true;
        else {
            // TODO: Test
            for (uint256 i; i < _features.length;) {
                addFeatureSupport(_features[i]);
                unchecked {
                    ++i;
                }
            }
        }

        address metadata = IFactory(IFactoryProvider(factoryProvider).factory()).tnftMetadata();
        (bool added,,) = ITNFTMetadata(metadata).tnftTypes(_tnftType);
        require(added, "Invalid tnftType");

        currencyFeed = ICurrencyFeedV2(_currencyFeed);
        primaryRentToken = IERC20Metadata(_rentToken);

        tnftType = _tnftType;
    }

    
    // ~ External Functions ~

    // TODO: Test
    function batchDepositTNFT(address[] memory _tangibleNFTs, uint256[] memory _tokenIds) external returns (uint256[] memory basketShares) {
        uint256 length = _tangibleNFTs.length;
        require(length == _tokenIds.length, "Arrays not same size");

        basketShares = new uint256[](length);

        for (uint256 i; i < length;) {
            basketShares[i] = depositTNFT(_tangibleNFTs[i], _tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method allows a user to deposit their TNFT in exchange for Basket tokens.
     */
    function depositTNFT(address _tangibleNFT, uint256 _tokenId) public returns (uint256 basketShare) {
        require(!tokenDeposited[_tangibleNFT][_tokenId], "Token already deposited");
        require(ITangibleNFTExt(_tangibleNFT).tnftType() == tnftType, "Token incompatible");

        uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

        if(activelySupportingFeature) {
            // if contract supports a feature, make sure tokenId has that feature
            uint256[] memory features = ITangibleNFT(_tangibleNFT).getTokenFeatures(_tokenId);
            bool supported;
            for (uint256 i; i < features.length;) {
                if (featureSupported[features[i]]) {
                    supported = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            require(supported, "TNFT missing feature");
        }

        (string memory currency, uint256 value, uint8 nativeDecimals) = _getTnftNativeValue(_tangibleNFT, fingerprint);

        uint256 usdValue = _getUSDValue(currency, value, nativeDecimals);
        require(usdValue > 0, "Unsupported TNFT");

        uint256 sharePrice = getSharePrice();
        basketShare = (usdValue * 10 ** decimals()) / sharePrice;

        IERC721(_tangibleNFT).safeTransferFrom(msg.sender, address(this), _tokenId);
        _mint(msg.sender, basketShare);

        tokenDeposited[_tangibleNFT][_tokenId] = true;
        depositedTnfts.push(TokenData(_tangibleNFT, _tokenId, fingerprint));

        currencyBalance[currency] += (value * 1e18) / 10 ** nativeDecimals;
        if (!currencySupported[currency]) {
            currencySupported[currency] = true;
            supportedCurrency.push(currency);
        }

        emit DepositedTNFT(msg.sender, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method allows a user to redeem a TNFT in exchange for their Basket tokens.
     */
    function redeemTNFT(address _tangibleNFT, uint256 _tokenId) external {
        // calc value of TNFT(s) being redeemed
            // value of TNFT(s) / total value of Basket
        
    }

    /**
     * @notice This method adds a feature subcategory to this Basket.
     */
    function addFeatureSupport(uint256 _feature) public onlyOwner {
        require(!activelySupportingFeature, "Feature already supported");
        address metadata = IFactory(IFactoryProvider(factoryProvider).factory()).tnftMetadata();
        require(ITNFTMetadata(metadata).featureInType(tnftType, _feature), "Feature not supported in type");

        activelySupportingFeature = true;
        featureSupported[_feature] = true;

        // Verify tokens that are already in basket have feature
        for (uint256 i; i < depositedTnfts.length;) {
            uint256[] memory features = ITangibleNFT(depositedTnfts[i].tnft).getTokenFeatures(depositedTnfts[i].tokenId);
            bool supported;
            for (uint256 j; j < features.length;) {
                if (featureSupported[features[j]]) {
                    supported = true;
                    break;
                }
                unchecked {
                    ++j;
                }
            }
            require(supported, "Incompatible TNFT in Basket");
            unchecked {
                ++i;
            }
        }

        emit FeatureSupportAdded(_feature);
    }

    // TODO: Refactor
    function removeFeatureSupport(uint256 _feature) external onlyOwner {
        require(featureSupported[_feature], "Feature not supported");

        activelySupportingFeature = false;
        featureSupported[_feature] = false;

        emit FeatureSupportRemoved(_feature);
    }

    function modifyRentTokenSupport(address _token, bool _support) external onlyFactoryOwner { // TODO: TEST
        (uint256 index, bool exists) = _isSupportedRentToken(_token);
        if (_support) {
            require(!exists, "Already supported");
            supportedRentToken.push(_token);
        }
        else {
            require(exists, "Not supported");
            supportedRentToken[index] = supportedRentToken[supportedRentToken.length - 1];
            supportedRentToken.pop();
        }
    }

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }


    // ~ Public Functions ~

    /**
     * @notice Return the USD value of share token for underlying assets, 18 decimals
     * @dev Underyling assets = TNFT + Accrued revenue
     */
    function getSharePrice() public view returns (uint256 sharePrice) {
        if (totalSupply() == 0) {
            // initial share price is $1
            return 1e18;
        }
        // Total value of collateral assets on basket, in 18 decimals
        uint256 collateralValue = getTotalValueOfBasket();

        sharePrice = (collateralValue * 10 ** decimals()) / totalSupply();

        require(sharePrice != 0, "share is 0");
    }

    function getTotalValueOfBasket() public view returns (uint256 totalValue) {
        // Get value of each real estate by currency
        for (uint256 i; i < supportedCurrency.length;) {
            totalValue += _getUSDValue(supportedCurrency[i], currencyBalance[supportedCurrency[i]], 18);
            unchecked {
                ++i;
            }
        }

        // get value of rent accrued by this contract
        //totalValue += _getUSDValue(primaryRentToken.symbol(), primaryRentToken.balanceOf(address(this)), primaryRentToken.decimals()); TODO: Revisit
    }

    function getDepositedTnfts() public view returns (TokenData[] memory) {
        return depositedTnfts;
    }

    function getSupportedRentTokens() public view returns (address[] memory) {
        return supportedRentToken;
    }


    // ~ Internal Functions ~

    /**
     * @dev Get value of TNFT in native currency
     */
    function _getTnftNativeValue(address _tangibleNFT, uint256 _fingerprint) internal view returns (string memory currency, uint256 value, uint8 decimals) {
        address factory = IFactoryProvider(factoryProvider).factory();

        ITangiblePriceManager priceManager = IFactory(factory).priceManager();
        //IPriceOracle oracle = priceManager.getPriceOracleForCategory(ITangibleNFT(_tangibleNFT));
        IPriceOracle oracle = ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFT));

        uint256 currencyNum;
        (value, currencyNum) = oracle.marketPriceNativeCurrency(_fingerprint);
        currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));

        decimals = oracle.decimals();
    }

    /**
     * @dev Get USD Value of given currency and amount, base 1e18
     */
    function _getUSDValue(string memory _currency, uint256 _amount, uint8 _amountDecimals) internal view returns (uint256) {
        (uint256 price, uint256 priceDecimals) = _getUsdExchangeRate(_currency);
        return (price * _amount * 10 ** 18) / 10 ** priceDecimals / 10 ** _amountDecimals;
    }

    /**
     * @dev Get USD Price of given currency from ChainLink
     */
    function _getUsdExchangeRate(string memory _currency) internal view returns (uint256, uint256) {
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(_currency);
        
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price < 0) price = 0;

        return (uint256(price), priceFeed.decimals());
    }

    /**
     * @notice This method returns whether a provided Erc20 token is supported for rent.
     */
    function _isSupportedRentToken(address _token) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < supportedRentToken.length;) {
            if (supportedRentToken[i] == _token) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }
}
