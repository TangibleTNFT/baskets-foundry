// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { ITangibleNFT } from "@tangible/interfaces/ITangibleNFT.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactoryProvider } from "@tangible/interfaces/IFactoryProvider.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";

import { Owned } from "./abstract/Owned.sol";

// TODO: How to handle rent? rent is redeemed when the TNFT is redeemed
// TODO: How to handle rev shares?
// TODO: Who is the owner of the contract? Creator or Tangible?
// TODO: How is rent sent to this contract? Time basis? What asset?

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
    }

    TokenData[] public depositedTokenIds;

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) public tokenDeposited;

    uint256 public immutable tnftType;

    uint256[] public supportedFeatures; // supported features

    mapping(uint256 => bool) public featureSupported;

    // string[] public supportedCurrency;

    // mapping(string => uint256) public currencyBalance;

    address[] public supportedRentToken; // rent token list

    uint256 public totalValueOfTNFTs;

    ICurrencyFeedV2 public currencyFeed;


    // ~ Events ~

    event DepositedTNFT(address prevOwner, address indexed tnft, uint256 indexed tokenId);


    // ~ Constructor ~

    /**
     * @notice Initializes Baskets contract.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _factoryProvider,
        uint256 _tnftType,
        address _currencyFeed
    )
        ERC20(_name, _symbol) 
        FactoryModifiers(_factoryProvider) 
        Owned(msg.sender) 
    {
        tnftType = _tnftType;
        currencyFeed = ICurrencyFeedV2(_currencyFeed);
    }

    
    // ~ External Functions ~

    /**
     * @notice This method allows a user to deposit their TNFT in exchange for Basket tokens.
     */
    function depositNft(address _tangibleNFT, uint256 _tokenId) external returns (uint256 basketShare) {
        require(!tokenDeposited[_tangibleNFT][_tokenId], "Token already deposited");
        // TODO: Require _tangibleNFT's tnfttype is == to tnftType
        // TODO: Verify token is of safe feature or type

        uint256 usdValue = _getUSDValueOfTnft(_tangibleNFT, _tokenId);
        require(usdValue > 0, "Unsupported TNFT");

        uint256 sharePrice = getSharePrice();
        basketShare = (usdValue * 10 ** decimals()) / sharePrice;

        IERC721(_tangibleNFT).safeTransferFrom(msg.sender, address(this), _tokenId);
        _mint(msg.sender, basketShare);

        tokenDeposited[_tangibleNFT][_tokenId] = true;
        depositedTokenIds.push(TokenData(_tangibleNFT, _tokenId));

        //(string memory currency, uint256 value, uint8 decimals) = _getTnftNativeValue(_tokenId);

        // currencyBalance[currency] += (value * 1e18) / 10 ** decimals; TODO: REVISIT
        // if (!currencySupported[currency]) {
        //     currencySupported[currency] = true;
        //     supportedCurrency.push(currency);
        // }

        emit DepositedTNFT(msg.sender, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method allows a user to redeem a TNFT in exchange for their Basket tokens.
     */
    function redeemNft(address _tangibleNFT, uint256 _tokenId) external {
        // calc value of TNFT(s) being redeemed
            // value of TNFT(s) / total value of Basket
        
    }

    function addFeatureSupport(uint256 _feature) external onlyOwner {
        // ensure it's not already supported
        // add it to array of supported
        // add it to mapping
    }

    function removeFeatureSupport(uint256 _feature) external onlyOwner {
        // ensure it's already supported
        // ensure there are no basket tokens in this contract that have this feature
        // remove it to array of supported
        // remove it from mapping
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

    /// NOTE: TESTING PURPOSES ONLY
    function updateTotalValue(uint256 _totalValue) external onlyOwner {
        totalValueOfTNFTs = _totalValue;
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
        uint256 collateralValue;

        // Get value of each real estate by currency
        // for (uint256 i; i < supportedCurrency.length;) { TODO: Come back to this
        //     collateralValue += _getUSDValue(supportedCurrency[i], currencyBalance[supportedCurrency[i]], 18);
        //     unchecked {
        //         ++i;
        //     }
        // }
        collateralValue += totalValueOfTNFTs;

        // Get value of all rent accrued by this contract
        for (uint256 i; i < supportedRentToken.length;) {
            IERC20Metadata rentToken = IERC20Metadata(supportedRentToken[i]);
            collateralValue += _getUSDValue(rentToken.symbol(), rentToken.balanceOf(address(this)), rentToken.decimals());

            unchecked {
                ++i;
            }
        }

        sharePrice = (collateralValue * 10 ** decimals()) / totalSupply();

        require(sharePrice != 0, "share is 0");
    }


    // ~ Internal Functions ~

    /**
     * @dev Get FingerPrint and USD value of given token id
     */
    function _getUSDValueOfTnft(address _tangibleNFT, uint256 _tnftTokenId) internal view returns (uint256 usdValue) {
        (string memory currency, uint256 value, uint8 decimals) = _getTnftNativeValue(_tangibleNFT, _tnftTokenId);
        usdValue = _getUSDValue(currency, value, decimals);
    }

    /**
     * @dev Get value of TNFT in native currency
     */
    function _getTnftNativeValue(address _tangibleNFT, uint256 _tnftTokenId) internal view returns (string memory currency, uint256 value, uint8 decimals) {
        uint256 fingerPrint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tnftTokenId); 
        address factory = IFactoryProvider(factoryProvider).factory();

        ITangiblePriceManager priceManager = IFactory(factory).priceManager();
        IPriceOracle oracle = priceManager.getPriceOracleForCategory(ITangibleNFT(_tangibleNFT));

        uint256 currencyNum;
        (value, currencyNum) = oracle.marketPriceNativeCurrency(fingerPrint);
        currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));

        decimals = oracle.decimals();
    }

    /**
     * @dev Get USD Value of given currency and amount, base 1e18
     */
    function _getUSDValue(string memory currency, uint256 amount, uint8 amountDecimals) internal view returns (uint256) {
        (uint256 price, uint256 priceDecimals) = _getUSDPrice(currency);
        return (price * amount * 10 ** 18) / 10 ** priceDecimals / 10 ** amountDecimals;
    }

    /**
     * @dev Get USD Price of given currency from ChainLink
     */
    function _getUSDPrice(string memory currency) internal view returns (uint256, uint256) {
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(currency);
        
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
        }
        return (0, false);
    }
}
