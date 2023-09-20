// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { ITangibleNFT, ITangibleNFTExt } from "@tangible/interfaces/ITangibleNFT.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";

import { IBasket } from "./interfaces/IBaskets.sol";
import { IBasketManager } from "./interfaces/IBasketsManager.sol";

// TODO: How to handle storage? Does this contract have to pay for storage? TBA
// TODO: Are there any other rewards besides rent? No
// TODO: How to handle total value? TBA

// NOTE: Make sure rev share and rent managers are updated properly
// NOTE: Test how proxy contracts can be implemented.

/**
 * @title Basket
 * @author Chase Brown
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is Initializable, ERC20Upgradeable, IBasket, FactoryModifiers {

    // ~ State Variables ~

    TokenData[] public depositedTnfts;

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) public tokenDeposited;

    mapping(uint256 => bool) public featureSupported;

    uint256[] public supportedFeatures;

    mapping(string => bool) public currencySupported;

    mapping(string => uint256) public currencyBalance;

    string[] public supportedCurrency; // TODO: Revisit -> https://github.com/TangibleTNFT/usdr/blob/master/contracts/TreasuryTracker.sol

    IERC20Metadata public primaryRentToken; // USDC by default

    uint256 public tnftType;

    address public deployer;

    uint256 public totalNftValue; // NOTE: For testing. Will be replaced


    // ~ Events ~

    event DepositedTNFT(address prevOwner, address indexed tnft, uint256 indexed tokenId);

    event RedeemedTNFT(address newOwner, address indexed tnft, uint256 indexed tokenId);

    event Debug(uint256);

    event FeatureSupportAdded(uint256 feature);

    event FeatureSupportRemoved(uint256 feature);


    // ~ Constructor ~

    constructor() FactoryModifiers(address(0)) {}

    /**
     * @notice Initializes Basket contract.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _factoryProvider,
        uint256 _tnftType,
        address _rentToken,
        uint256[] memory _features,
        address _deployer
    ) external initializer {   
        require(_factoryProvider != address(0), "FactoryProvider == address(0)");
        
        // If _features is not empty, add features
        if (_features.length > 0) {
            for (uint256 i; i < _features.length;) {
                supportedFeatures.push(_features[i]);
                featureSupported[_features[i]] = true;

                unchecked {
                    ++i;
                }
            }
        }

        __ERC20_init(_name, _symbol);
        __FactoryModifiers_init(_factoryProvider);

        tnftType = _tnftType;
        deployer = _deployer;

        primaryRentToken = IERC20Metadata(_rentToken);
    }

    
    // ~ External Functions ~

    /**
     * @notice This method allows a user to deposit a batch of TNFTs into the basket.
     */
    function batchDepositTNFT(address[] memory _tangibleNFTs, uint256[] memory _tokenIds) external returns (uint256[] memory basketShares) {
        uint256 length = _tangibleNFTs.length;
        require(length == _tokenIds.length, "Arrays not same size");

        basketShares = new uint256[](length);

        for (uint256 i; i < length;) {
            basketShares[i] = _depositTNFT(_tangibleNFTs[i], _tokenIds[i], msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method allows a user to deposit their TNFT in exchange for Basket tokens.
     */
    function depositTNFT(address _tangibleNFT, uint256 _tokenId) external returns (uint256 basketShare) {
        basketShare = _depositTNFT(_tangibleNFT, _tokenId, msg.sender);
    }

    function _depositTNFT(address _tangibleNFT, uint256 _tokenId, address _depositor) internal returns (uint256 basketShare) {
        require(!tokenDeposited[_tangibleNFT][_tokenId], "Token already deposited");
        require(ITangibleNFTExt(_tangibleNFT).tnftType() == tnftType, "Token incompatible");

        // get token fingerprint
        uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = true;
        depositedTnfts.push(TokenData(_tangibleNFT, _tokenId, fingerprint));

        // if contract supports features, make sure tokenId has a supported feature
        uint256 length = supportedFeatures.length;
        if(length > 0) {
            for (uint256 i; i < length;) {
                bool supported;

                ITangibleNFT.FeatureInfo memory featureData = ITangibleNFTExt(_tangibleNFT).tokenFeatureAdded(_tokenId, supportedFeatures[i]);
                if (featureData.added) supported = true;

                require(supported, "TNFT missing feature");
                unchecked {
                    ++i;
                }
            }
        }

        // take token from depositor
        IERC721(_tangibleNFT).safeTransferFrom(msg.sender, address(this), _tokenId);

        // find value of TNFT
        (string memory currency, uint256 value, uint8 nativeDecimals) = _getTnftNativeValue(_tangibleNFT, fingerprint);

        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = _getUSDValue(currency, value, nativeDecimals);
        require(usdValue > 0, "Unsupported TNFT");

        // find share price
        uint256 sharePrice = getSharePrice();
        basketShare = (usdValue * 10 ** decimals()) / sharePrice; // TODO: Revisit

        // if msg.sender is basketManager, it's making an initial deposit -> receiver of basket tokens needs to be deployer.
        if (msg.sender == IFactory(IFactoryProvider(factoryProvider).factory()).basketsManager()) {
            _depositor = deployer;
        }

        // mint basket tokens to user
        _mint(_depositor, basketShare);

        currencyBalance[currency] += (value * 1e18) / 10 ** nativeDecimals; // NOTE: Will most likely be removed
        if (!currencySupported[currency]) {
            currencySupported[currency] = true;
            supportedCurrency.push(currency);
        }

        totalNftValue += usdValue;

        emit DepositedTNFT(_depositor, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method allows a user to redeem a TNFT in exchange for their Basket tokens.
     */
    function redeemTNFT(address _tangibleNFT, uint256 _tokenId, uint256 _amountBasketTokens) external {
        _redeemTNFT(_tangibleNFT, _tokenId, _amountBasketTokens);
    }

    function _redeemTNFT(address _tangibleNFT, uint256 _tokenId, uint256 _amountBasketTokens) internal {

        // calc value of TNFT(s) being redeemed
            // value of TNFT(s) / total value of Basket
        
        // calculate value of TNFT being redeemed
            // how to calculate this?
        // ensure user has sufficient TBT basket tokens
        // take tokens
        // send TNFT
        // calculate amount of rent to send
            // rent * total supply / amountTokens

        require(balanceOf(msg.sender) >= _amountBasketTokens, "Insufficient balance");
        require(tokenDeposited[_tangibleNFT][_tokenId], "Invalid token");

        // Transfer tokenId to user -> update contract accordingly.
        IERC721(_tangibleNFT).safeTransferFrom(address(this), msg.sender, _tokenId);

        uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);
        (string memory currency, uint256 value, uint8 nativeDecimals) = _getTnftNativeValue(_tangibleNFT, fingerprint);

        uint256 usdValue = _getUSDValue(currency, value, nativeDecimals);
        require(usdValue > 0, "Unsupported TNFT");
        emit Debug(usdValue);

        // Use usdValue and sharePrice to calculate how many tokens the user must have based on current market value of TNFT being redeemed.
        uint256 sharePrice = getSharePrice();
        emit Debug(sharePrice); // NOTE: For testing only

        // Get rent balance of contract
        uint256 rentBal = getRentBal();

        // Calculate amount of rent to send to redeemer
        uint256 amountRent = (usdValue * rentBal) / totalNftValue; // TODO: Test, revisit
        emit Debug(amountRent); // NOTE: For testing only

        // Calculate amount of basket tokens needed. Usd value of NFT + rent amount / share price == total basket tokens.
        uint256 basketSharesRequired = ((usdValue + (amountRent * 10**12)) / sharePrice) * 10 ** decimals();
        emit Debug(basketSharesRequired); // NOTE: For testing only

        // Verify the user has this amount of tokens -> If so, BURN them (user will have to approve prior)
        require(_amountBasketTokens >= basketSharesRequired, "Insufficient offer");
        if (_amountBasketTokens > basketSharesRequired) _amountBasketTokens = basketSharesRequired;
        emit Debug(_amountBasketTokens); // NOTE: For testing only

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = false;
        currencyBalance[currency] -= (value * 1e18) / 10 ** nativeDecimals; // NOTE: Will most likely be removed

        (uint256 index,) = _isDepositedTnft(_tangibleNFT, _tokenId);
        depositedTnfts[index] = depositedTnfts[depositedTnfts.length - 1];
        depositedTnfts.pop();

        // Send rent to redeemer
        if (amountRent > 0) {
            //uint256 amountRent = (usdValue * rentBal) / totalNftValue; // TODO: Test, revisit
            assert(primaryRentToken.transfer(msg.sender, amountRent));
        }

        totalNftValue -= usdValue;
        _burn(msg.sender, _amountBasketTokens);

        emit RedeemedTNFT(msg.sender, _tangibleNFT, _tokenId);
    }

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function getDepositedTnfts() external view returns (TokenData[] memory) {
        return depositedTnfts;
    }

    function getSupportedFeatures() external view returns (uint256[] memory) {
        return supportedFeatures;
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
        // TODO: Convert decimals
        totalValue += (getRentBal() * 10 ** (decimals() - primaryRentToken.decimals())); // TODO: Revisit -> USDC oracle may be best in case of a depeg.
    }

    function getRentBal() public view returns (uint256) {
        return primaryRentToken.balanceOf(address(this));
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

        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(IFactoryProvider(factoryProvider).factory()).currencyFeed());
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
        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(IFactoryProvider(factoryProvider).factory()).currencyFeed());
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(_currency);
        
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price < 0) price = 0;

        return (uint256(price), priceFeed.decimals());
    }

    /**
     * @notice This method returns whether a provided TNFT token exists in this contract and if so, where in the array.
     */
    function _isDepositedTnft(address _tnft, uint256 _tokenId) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < depositedTnfts.length;) {
            if (depositedTnfts[i].tnft == _tnft && depositedTnfts[i].tokenId == _tokenId) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }
}
