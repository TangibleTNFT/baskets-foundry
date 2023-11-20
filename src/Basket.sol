// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// oz imports
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// chainlink imports
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// tangible imports
import { ITangibleNFT, ITangibleNFTExt } from "@tangible/interfaces/ITangibleNFT.sol";
import { FactoryModifiers } from "@tangible/abstract/FactoryModifiers.sol";
import { IFactory } from "@tangible/interfaces/IFactory.sol";
import { ITangiblePriceManager } from "@tangible/interfaces/ITangiblePriceManager.sol";
import { IPriceOracle } from "@tangible/interfaces/IPriceOracle.sol";
import { ICurrencyFeedV2 } from "@tangible/interfaces/ICurrencyFeedV2.sol";
import { ITNFTMetadata } from "@tangible/interfaces/ITNFTMetadata.sol";
import { IOwnable } from "@tangible/interfaces/IOwnable.sol";
import { IRentManager, IRentManagerExt } from "@tangible/interfaces/IRentManager.sol";
import { IRWAPriceNotificationReceiver } from "@tangible/notifications/IRWAPriceNotificationReceiver.sol";
import { IRWAPriceNotificationDispatcher } from "@tangible/interfaces/IRWAPriceNotificationDispatcher.sol";
import { INotificationWhitelister } from "@tangible/interfaces/INotificationWhitelister.sol";
import { IChainlinkRWAOracle } from "@tangible/interfaces/IChainlinkRWAOracle.sol";

// local imports
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketManager.sol";
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "./interfaces/IGetNotificationDispatcher.sol";
import { IGetOracle } from "./interfaces/IGetOracle.sol";
import { RebaseTokenUpgradeable } from "@tangible-foundation-contracts/tokens/RebaseTokenUpgradeable.sol";


/**
 * @title Basket
 * @author Chase Brown
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is Initializable, RebaseTokenUpgradeable, IBasket, IRWAPriceNotificationReceiver, ReentrancyGuardUpgradeable, FactoryModifiers {

    // ---------------
    // State Variables
    // ---------------

    /// @notice Ledger of all TNFT tokens stored in this basket.
    TokenData[] public depositedTnfts;

    /// @notice Array of TNFT contract addresses supported by this contract.
    address[] public tnftsSupported;

    /// @notice Mapping of TNFT contract address => array of tokenIds in this basket from each TNFT contract.
    mapping(address => uint256[]) public tokenIdLibrary;

    /// @notice Mapping used to track the usdValue of each TNFT token in this contract.
    mapping(address => mapping(uint256 => uint256)) public valueTracker;

    /// @notice TangibleNFT contract => tokenId => if deposited into address(this).
    mapping(address => mapping(uint256 => bool)) public tokenDeposited;

    /// @notice Mapping used to check whether a specified feature (key) is supported. If true, feature is required.
    mapping(uint256 => bool) public featureSupported;

    /// @notice Array of all features required by a TNFT token to be deposited into this basket.
    /// @dev These features (aka "subcategories") are OPTIONAL.
    uint256[] public supportedFeatures;

    /// @notice TnftType that this basket supports exclusively.
    /// @dev This TnftType (aka "category") is REQUIRED upon basket creation.
    uint256 public tnftType;

    /// @notice This value is used to track the total USD value of all TNFT tokens inside this contract.
    uint256 public totalNftValue;

    /// @notice This value stores the amount of rent claimable by this contract. Updated upon rebase.
    uint256 public totalRentValue;

    /// @notice Stores the fee taken upon a deposit. Uses 2 basis points (i.e. 2% == 200)
    uint16 public depositFee; // 0.5% by default

    /// @notice Stores the ISO country code for location this basket supports.
    uint16 public location;

    /// @notice If true, there is an outstanding request to Chainlink vrf that has yet to be fulfilled.
    bool public seedRequestInFlight;

    /// @notice This stores a reference to the primary ERC-20 token used for paying out rent.
    IERC20Metadata public primaryRentToken; // USTB by default

    /// @notice Address of basket creator.
    address public deployer;

    /// @notice If there is a pending, unfulfilled, Chainlink vrf request, the requestId will be stored here.
    uint256 public pendingSeedRequestId;

    /// @notice This stores the data for the next NFT that is elgible for redemption.
    RedeemData public nextToRedeem;

    /// @notice Stores the fee taken upon a deposit. Uses 2 basis points (i.e. 10% == 1000)
    uint16 public rentFee; // 10% by default


    // ------
    // Events
    // ------

    /**
     * @notice This event is emitted when a TNFT is deposited into this basket.
     * @param prevOwner Previous owner before deposit. Aka depositor.
     * @param tnft TNFT contract address of token being deposited.
     * @param tokenId TokenId identifier of token being deposited.
     */
    event TNFTDeposited(address indexed prevOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when a TNFT is redeemed from this basket.
     * @param newOwner New owner before deposit. Aka redeemer.
     * @param tnft TNFT contract address of token being redeemed.
     * @param tokenId TokenId identifier of token being redeemed.
     */
    event TNFTRedeemed(address indexed newOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when the price of a TNFT token is updated by the oracle.
     * @param tnft TNFT contract address of token being updated.
     * @param tokenId TokenId identifier of token being updated.
     * @param oldPrice Old USD price of TNFT token.
     * @param newPrice New USD price of TNFT token.
     */
    event PriceNotificationReceived(address indexed tnft, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);

    /**
     * @notice This event is emitted when a successful request to vrf has been made.
     * @param requestId Request identifier returned by Chainlink's Vrf Coordinator contract.
     */
    event RequestSentToVrf(uint256 requestId);

    /**
     * @notice This event is emitted when `fulfillRandomSeed` is successfully executed and a new `nextToRedeem` was assigned.
     * @param tnft Tangible NFT contract address of NFT redeemable.
     * @param tokenId TokenId of NFT redeemable.
     */
    event RedeemableChosen(address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when `rebase` is successfully executed.
     * @param caller msg.sender that called `rebase`
     * @param newTotalRentValue New value assigned to `totalRentValue`.
     * @param newRebaseIndex New multiplier used for calculating rebase tokens.
     */
    event RebaseExecuted(address caller, uint256 newTotalRentValue, uint256 newRebaseIndex);


    // ---------
    // Modifiers
    // ---------

    /// @notice This modifier is to verify msg.sender is the BasketVrfConsumer constract.
    modifier onlyBasketVrfConsumer() {
        require(msg.sender == _getBasketVrfConsumer());
        _;
    }


    // -----------
    // Constructor
    // -----------

    constructor() {
        _disableInitializers();
    }


    // -----------
    // Initializer
    // -----------

    /**
     * @notice Initializes Basket contract.
     * @param _name Unique name of basket contract.
     * @param _symbol Unique symbol of basket contract.
     * @param _factoryProvider FactoryProvider contract address.
     * @param _tnftType TNFT Type (category).
     * @param _rentToken ERC-20 token being used for rent. USTB by default.
     * @param _features Array of features TNFTs must support to be in this basket.
     * @param _location ISO country code for supported location of basket.
     * @param _deployer Address of creator of the basket contract.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _factoryProvider,
        uint256 _tnftType,
        address _rentToken,
        uint256[] memory _features,
        uint16 _location,
        address _deployer
    ) external initializer {   
        require(_factoryProvider != address(0), "FactoryProvider == address(0)");
        
        // If _features is not empty, add features
        for (uint256 i; i < _features.length;) {
            supportedFeatures.push(_features[i]);
            featureSupported[_features[i]] = true;

            unchecked {
                ++i;
            }
        }

        depositFee = 50; // 0.5%
        rentFee = 1000; // 10.0%

        location = _location;

        __RebaseToken_init(_name, _symbol);
        __FactoryModifiers_init(_factoryProvider);

        _setRebaseIndex(1 ether);

        tnftType = _tnftType;
        deployer = _deployer;

        primaryRentToken = IERC20Metadata(_rentToken);
    }


    // ----------------
    // External Methods
    // ----------------

    /**
     * @notice This method allows a user to deposit a batch of TNFTs into the basket.
     * @dev Gas block limit is reached at ~200 tokens.
     * @param _tangibleNFTs Array of TNFT contract addresses corresponding with each token being deposited.
     * @param _tokenIds Array of token Ids being deposited.
     * @return basketShares -> Array of basket tokens minted to msg.sender for each token deposited.
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
     * @param _tangibleNFT TNFT contract address of token being deposited.
     * @param _tokenId TNFT tokenId of token being deposited.
     * @return basketShare -> Amount of basket tokens minted to msg.sender.
     */
    function depositTNFT(address _tangibleNFT, uint256 _tokenId) external returns (uint256 basketShare) {
        basketShare = _depositTNFT(_tangibleNFT, _tokenId, msg.sender);
    }

    /**
     * @notice This method is used to redeem a TNFT token. This method will take a budget of basket tokens and
     *         if the budget is sufficient will transfer the NFT stored in `nextToRedeem` to the msg.sender.
     * @dev Burns basket tokens 1-1 with usdValue of token redeemed.
     * @param _budget Amount of basket tokens being submitted to redeem method.
     */
    function redeemTNFT(uint256 _budget) external {
        _redeemTNFT(msg.sender, _budget);
    }

    /**
     * @notice This method is executed upon the callback of vrf for entropy. This method will use the randomWord to select
     *         a ranom index from the `depositedTnfts` array to be next redeemable NFT.
     * @param randomWord Random uint seed received from vrf.
     */
    function fulfillRandomSeed(uint256 randomWord) external onlyBasketVrfConsumer {

        // choose a nft to be next redeemable

        uint256 index;
        index = randomWord % depositedTnfts.length;

        address tnft = depositedTnfts[index].tnft;
        uint256 tokenId = depositedTnfts[index].tokenId;

        nextToRedeem = RedeemData(tnft, tokenId);
        emit RedeemableChosen(tnft, tokenId);
        
        seedRequestInFlight = false;
        pendingSeedRequestId = 0;
    }

    /**
     * @notice This method allows the factory owner to manually send a request for entropy to vrf.
     * @dev This method should only be used as a last resort if a vrf callback reverts or if there resides a stale redeemable.
     * @return requestId -> request identifier created by vrf coordinator.
     */
    function sendRequestForSeed() external onlyFactoryOwner returns (uint256 requestId) {
        return _sendRequestForSeed();
    }

    /**
     * @notice Internal method that handles making requests to vrf through the BasketsVrfConsumer contract.
     * @return requestId -> request identifier created by vrf coordinator.
     */
    function _sendRequestForSeed() internal returns (uint256 requestId) {
        if (depositedTnfts.length != 0) {
            seedRequestInFlight = true;

            requestId = IBasketsVrfConsumer(_getBasketVrfConsumer()).makeRequestForRandomWords();

            pendingSeedRequestId = requestId;
            emit RequestSentToVrf(requestId);
        }
    }

    /**
     * @notice ALlows this contract to get notified of a price change
     * @dev Defined on interface IRWAPriceNotificationReceiver::notify
     * @param _tnft TNFT contract address of token being updated.
     * @param _tokenId TNFT tokenId of token being updated.
     */
    function notify(
        address _tnft,
        uint256 _tokenId,
        uint256, // fingerprint
        uint256, // oldNativePrice
        uint256, // newNativePrice
        uint16   // currency
    ) external {
        require(msg.sender == address(_getNotificationDispatcher(_tnft)),
            "msg.sender != ND"
        );

        uint256 oldPriceUsd = valueTracker[_tnft][_tokenId];
        uint256 newPriceUsd = _getUSDValue(_tnft, _tokenId);

        valueTracker[_tnft][_tokenId] = newPriceUsd;
        totalNftValue = (totalNftValue - oldPriceUsd) + newPriceUsd;

        emit PriceNotificationReceived(_tnft, _tokenId, oldPriceUsd, newPriceUsd);
    }

    /**
     * @notice This method allows the factory owner to update the `primaryRentToken` state variable.
     * @dev If the rent token is being changed indefinitely, make sure to change the address of the rent token being used
     *      to initialize new baskets on the BasketManager.
     * @param _primaryRentToken New address for `primaryRentToken`.
     */
    function updatePrimaryRentToken(address _primaryRentToken) external onlyFactoryOwner {
        require(_primaryRentToken != address(0), "Cannot be == address(0)");
        primaryRentToken = IERC20Metadata(_primaryRentToken);
    }

    /**
     * @notice This onlyFactoryOwner method allows a factory owner to withdraw a specified amount of claimable rent from this basket.
     * @param _withdrawAmount Amount of rent to withdraw. note: Should input with basis points == `primaryRentToken.decimals()`.
     */
    function withdrawRent(uint256 _withdrawAmount) external onlyFactoryOwner {
        _transferRent(msg.sender, _withdrawAmount);
    }

    /**
     * @notice This method is used to quote a batch amount of basket tokens transferred to depositor if a specfied token is deposted.
     * @dev Does NOT include the amount of basket tokens subtracted for deposit fee.
     *      The amount of tokens quoted will be slightly different if the same tokens are deposited via batchDepositTNFT.
     *      Reason being, when tokens are deposited sequentially via batch, the share price will fluctuate in between deposits.
     * @param _tangibleNFTs Array of TangibleNFT contract addresses of NFTs being quoted.
     * @param _tokenIds Array of TokenIds of NFTs being quoted.
     * @return shares -> Array of Erc20 basket tokens quoted for each NFT respectively.
     */
    function getBatchQuoteIn(address[] memory _tangibleNFTs, uint256[] memory _tokenIds) external view returns (uint256[] memory shares) {
        uint256 len = _tangibleNFTs.length;
        shares = new uint256[](len);
        for (uint i; i < len;) {

            // calculate usd value of TNFT with 18 decimals
            uint256 usdValue = _getUSDValue(_tangibleNFTs[i], _tokenIds[i]);
            require(usdValue > 0, "Unsupported TNFT");

            // calculate shares for depositor
            shares[i] = _quoteShares(usdValue);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice This method is used to quote an amount of basket tokens transferred to depositor if a specfied token is deposted.
     * @dev Does NOT include the amount of basket tokens subtracted for deposit fee.
     * @param _tangibleNFT TangibleNFT contract address of NFT being quoted.
     * @param _tokenId TokenId of NFT being quoted.
     * @return shares -> Amount of Erc20 basket tokens quoted for NFT.
     */
    function getQuoteIn(address _tangibleNFT, uint256 _tokenId) external view returns (uint256 shares) {
        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = _getUSDValue(_tangibleNFT, _tokenId);
        require(usdValue > 0, "Unsupported TNFT");

        // calculate shares for depositor
        shares = _quoteShares(usdValue);
    }

    /**
     * @notice This method is used to quote an amount of basket tokens required if a specfiied token is redeemed.
     * @param _tangibleNFT TangibleNFT contract address of NFT being quoted.
     * @param _tokenId TokenId of NFT being quoted.
     * @return sharesRequired -> Amount of Erc20 basket tokens required to redeem NFT.
     */
    function getQuoteOut(address _tangibleNFT, uint256 _tokenId) external view returns (uint256 sharesRequired) {
        // fetch usd value of tnft
        uint256 usdValue = valueTracker[_tangibleNFT][_tokenId];
        require(usdValue != 0, "Unsupported TNFT");

        // Get shares required
        sharesRequired = _quoteShares(usdValue);
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @dev Returns an amount of `primaryRentToken` in contract + claimable from rent manager.
     * @param totalRent Total claimable rent balance of TNFTs inside basket.
     */
    function getRentBal() external view returns (uint256 totalRent) {
        return _getRentBal();
    }

    /**
     * @notice This method returns the `depositedTnfts` state array in it's entirety.
     */
    function getDepositedTnfts() external view returns (TokenData[] memory) {
        return depositedTnfts;
    }

    /**
     * @notice This method returns the `tnftsSupported` state array in it's entirety.
     */
    function getTnftsSupported() external view returns (address[] memory) {
        return tnftsSupported;
    }

    /**
     * @notice This method returns the `tokenIdLibrary` mapped array in it's entirety.
     * @param _tnft TNFT contract address specifying the array desired from the mapping.
     */
    function getTokenIdLibrary(address _tnft) external view returns (uint256[] memory) {
        return tokenIdLibrary[_tnft];
    }

    /**
     * @notice This method returns the `supportedFeatures` state array in it's entirety.
     */
    function getSupportedFeatures() external view returns (uint256[] memory) {
        return supportedFeatures;
    }

    /**
     * @notice Allows address(this) to receive ERC721 tokens.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    
    // --------------
    // Public Methods
    // --------------

    /**
     * @notice This function allows for the Basket token to "rebase" and will update the multiplier based
     * on the amount of rent accrued by the basket tokens.
     */
    function rebase() public {
        uint256 previousRentalIncome = totalRentValue;
        uint256 totalRentalIncome = _getRentBal();
    
        uint256 collectedRent = totalRentalIncome - previousRentalIncome;

        // Take 10% off collectedRent and send to revenue contract
        uint256 rentDistribution = (collectedRent * rentFee) / 100_00;
        collectedRent -= rentDistribution;

        uint256 rebaseIndexDelta = (collectedRent * decimalsDiff()) * 1e18 / getTotalValueOfBasket();

        uint256 rebaseIndex = rebaseIndex();

        rebaseIndex += rebaseIndexDelta;
        totalRentValue = totalRentalIncome;

        _transferRent(_getRevenueShare(), rentDistribution);
        _setRebaseIndex(rebaseIndex);

        emit RebaseExecuted(msg.sender, totalRentValue, rebaseIndex);
    }

    /**
     * @notice Return the USD value of share token for underlying assets, 18 decimals
     * @dev Underyling assets = TNFT + Accrued revenue
     */
    function getSharePrice() public view returns (uint256 sharePrice) {
        if (totalSupply() == 0) {
            // initial share price is $1
            return 1e18;
        }

        sharePrice = (getTotalValueOfBasket() * 10 ** decimals()) / totalSupply();
    }

    /**
     * @notice This method returns the total value of NFTs and claimable rent in this basket contract.
     * @return totalValue -> total value in 18 decimals.
     */
    function getTotalValueOfBasket() public view returns (uint256 totalValue) {
        unchecked {
            // get total value of nfts in basket.
            totalValue += totalNftValue;

            // get value of rent accrued by this contract.
            totalValue += totalRentValue * decimalsDiff();
        }
    }

    /**
     * @notice This view method returns true if a specified token contains the features needed to be deposited into this basket.
     * @param _tangibleNFT TNFT contract address of token.
     * @param _tokenId TokenId of token.
     * @return If true, token is compatible and can be deposited into this basket contract.
     */
    function isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) public view returns (bool) {
        // a. Check supported TNFTType (category)
        if (ITangibleNFTExt(_tangibleNFT).tnftType() != tnftType) return false;

        uint256 length = supportedFeatures.length;

        // b. Check supported features, if any (sub-category)
        for (uint256 i; i < length;) {

            ITangibleNFT.FeatureInfo memory featureData = ITangibleNFTExt(_tangibleNFT).tokenFeatureAdded(_tokenId, supportedFeatures[i]);
            if (!featureData.added) return false;

            unchecked {
                ++i;
            }
        }

        // c. Check supported location, if any
        if (location != 0) {

            uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

            IChainlinkRWAOracle oracle = IGetOracle(address(_getOracle(_tangibleNFT))).chainlinkRWAOracle();
            IChainlinkRWAOracle.Data memory data = oracle.fingerprintData(fingerprint);

            if (data.location != location) return false;
        }

        return true;
    }

    /**
     * @notice This method provides an easy way to fetch the decimal difference between the `primaryRentToken` and
     *         the basket's native 18 decimals.
     * @return decimalsDiff -> If the difference of decimals is gt 0, it will return 10**x (x being the difference).
     *         This can make converting basis points much easier. However, if the difference is == 0, will just return 1.
     */
    function decimalsDiff() public view returns (uint256 decimalsDiff) {
        uint256 decimalsDiff = decimals() - primaryRentToken.decimals();
        if (decimalsDiff != 0) {
            return 10 ** decimalsDiff;
        }
        else return 1;
    }


    // ----------------
    // Internal Methods
    // ----------------

    /**
     * @notice This internal method is used to deposit a specified TNFT from a depositor address to this basket.
     *         The deposit will be minted a sufficient amount of basket tokens in return.
     * @dev Any unclaimed rent claimable from the rent manager is claimed and transferred to the depositor.
     * @param _tangibleNFT TNFT contract address of token being deposited.
     * @param _tokenId TokenId of token being deposited.
     * @param _depositor Address depositing the token.
     * @return basketShare -> Amount of basket tokens being minted to redeemer.
     */
    function _depositTNFT(address _tangibleNFT, uint256 _tokenId, address _depositor) internal nonReentrant returns (uint256 basketShare) {
        require(!tokenDeposited[_tangibleNFT][_tokenId], "Token already deposited");

        // if contract supports features, make sure tokenId has a supported feature
        require(isCompatibleTnft(_tangibleNFT, _tokenId), "Token incompatible");

        // get token fingerprint
        uint256 fingerprint = ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId);

        // calculate usd value of TNFT with 18 decimals
        uint256 usdValue = _getUSDValue(_tangibleNFT, _tokenId);
        require(usdValue > 0, "Unsupported TNFT");

        // ~ Update contract state ~

        tokenDeposited[_tangibleNFT][_tokenId] = true;
        valueTracker[_tangibleNFT][_tokenId] = usdValue;

        depositedTnfts.push(TokenData(_tangibleNFT, _tokenId, fingerprint));
        tokenIdLibrary[_tangibleNFT].push(_tokenId);

        (, bool exists) = _isSupportedTnft(_tangibleNFT);
        if (!exists) {
            tnftsSupported.push(_tangibleNFT);
        }

        // take token from depositor
        IERC721(_tangibleNFT).safeTransferFrom(msg.sender, address(this), _tokenId);
        
        // register for price notifications
        IRWAPriceNotificationDispatcher notificationDispatcher = _getNotificationDispatcher(_tangibleNFT);

        require(INotificationWhitelister(address(notificationDispatcher)).whitelistedReceiver(address(this)), "Basket not WL on ND");
        INotificationWhitelister(address(notificationDispatcher)).registerForNotification(_tokenId);

        // ~ Calculate basket tokens to mint ~

        // get quoted shares
        basketShare = _quoteShares(usdValue);

        // if msg.sender is basketManager, it's making an initial deposit -> receiver of basket tokens needs to be deployer.
        if (msg.sender == IFactory(factory()).basketsManager()) {
            _depositor = deployer;
        }
        else {
            // if deposit isn't initial deposit from deployer (which will be most cases), charge a deposit fee.
            uint256 feeShare = (basketShare * uint256(depositFee)) / 100_00;
            basketShare -= feeShare;
        }

        // ~ Handle rent ~

        // claim rent for TNFT being redeemed.
        IRentManager rentManager = _getRentManager(_tangibleNFT);

        if (rentManager.claimableRentForToken(_tokenId) != 0) {
            uint256 preBal = primaryRentToken.balanceOf(address(this));
            uint256 receivedRent;

            unchecked {
                receivedRent += rentManager.claimRentForToken(_tokenId);
            }

            // verify claimed balance, send rent to depositor.
            require(primaryRentToken.balanceOf(address(this)) == (preBal + receivedRent), "claiming error");
            assert(primaryRentToken.transfer(address(_depositor), receivedRent));
        }

        // ~ Mint tokens to depositor ~

        // mint basket tokens to user
        _mint(_depositor, basketShare);

        // Update total nft value in this contract
        unchecked {
            totalNftValue += usdValue;
        }

        // if there is no seed request in flight and no nextToRedeem, make request
        if ((nextToRedeem.tnft == address(0)) && (!seedRequestInFlight)) {
            if (depositedTnfts.length == 1) {
                // if first deposit, just assign first in to next redeem
                nextToRedeem = RedeemData(_tangibleNFT, _tokenId);
            }
            else {
                // if no request was made or fulfilled, but contract has more than 1 token in basket, send request.
                // could happen if request for entropy was made, but failed on callback
                _sendRequestForSeed();
            }
        }

        emit TNFTDeposited(_depositor, _tangibleNFT, _tokenId);
    }

    /**
     * @notice Internal method for redeeming a specified TNFT from this basket contract.
     * @param _redeemer EOA address of redeemer. note: msg.sender
     * @param _budget Budget of basket tokens willing to redeem
     */
    function _redeemTNFT(
        address _redeemer,
        uint256 _budget
    ) internal nonReentrant {
        require(balanceOf(_redeemer) >= _budget, "Insufficient balance");
        require(!seedRequestInFlight, "new seed is being generated");
        require(nextToRedeem.tnft != address(0), "None redeemable");

        address _tangibleNFT = nextToRedeem.tnft;
        uint256 _tokenId = nextToRedeem.tokenId;
        uint256 _usdValue = valueTracker[_tangibleNFT][_tokenId];
        uint256 _sharesRequired = _quoteShares(_usdValue);

        delete nextToRedeem;

        require(tokenDeposited[_tangibleNFT][_tokenId], "Invalid token");
        require(_budget >= _sharesRequired, "Insufficient budget");

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = false;

        uint256 index;
        (index,) = _isDepositedTnft(_tangibleNFT, _tokenId);
        depositedTnfts[index] = depositedTnfts[depositedTnfts.length - 1];
        depositedTnfts.pop();

        (index,) = _isTokenIdLibrary(_tangibleNFT, _tokenId);
        tokenIdLibrary[_tangibleNFT][index] = tokenIdLibrary[_tangibleNFT][tokenIdLibrary[_tangibleNFT].length - 1];
        tokenIdLibrary[_tangibleNFT].pop();

        if (tokenIdLibrary[_tangibleNFT].length == 0) {
            (index,) = _isSupportedTnft(_tangibleNFT); 
            tnftsSupported[index] = tnftsSupported[tnftsSupported.length - 1];
            tnftsSupported.pop();
        }

        IRentManager rentManager = _getRentManager(_tangibleNFT);

        // redeem rent from redeemed TNFT to this contract.
        if (rentManager.claimableRentForToken(_tokenId) > 0) {
            uint256 preBal = primaryRentToken.balanceOf(address(this));
            uint256 received = rentManager.claimRentForToken(_tokenId);
            require(primaryRentToken.balanceOf(address(this)) == (preBal + received), "claiming error");
        }

        // unregister from price notifications
        IRWAPriceNotificationDispatcher notificationDispatcher = _getNotificationDispatcher(_tangibleNFT);
        INotificationWhitelister(address(notificationDispatcher)).unregisterForNotification(_tokenId);

        // Transfer tokenId to user
        IERC721(_tangibleNFT).safeTransferFrom(address(this), _redeemer, _tokenId);

        totalNftValue -= _usdValue;
        _burn(_redeemer, _sharesRequired);

        // fetch new seed
        _sendRequestForSeed();

        emit TNFTRedeemed(_redeemer, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method will transfer an arbitrary amount of `primaryRentToken` to a specified recipient.
     * @dev Will claim any rent from the rent manager that is needed if balanceOf(address(this)) is not sufficient.
     * @param _recipient Recipient of `primaryRentToken`.
     * @param _withdrawAmount Amount of `primaryRentToken` to transfer to `_recipient`.
     */
    function _transferRent(address _recipient, uint256 _withdrawAmount) internal {
        require(totalRentValue >= _withdrawAmount, "Amount exceeds withdrawable rent");

        // if we still need more rent, start claiming rent from TNFTs in basket.
        if (_withdrawAmount > primaryRentToken.balanceOf(address(this))) {

            // declare master array to store all claimable rent data.
            RentData[] memory claimableRent = new RentData[](depositedTnfts.length);
            uint256 counter;

            // iterate through all TNFT contracts supported by this basket.
            for (uint256 i; i < tnftsSupported.length;) {
                address tnft = tnftsSupported[i];

                // for each TNFT supported, make a batch call to the rent manager for all rent claimable for the array of tokenIds.
                uint256[] memory claimables = _getRentManager(tnft).claimableRentForTokenBatch(tokenIdLibrary[tnft]);

                // iterate through the array of claimable rent for each tokenId for each TNFT and push it to the master claimableRent array.
                for (uint256 j; j < claimables.length;) {
                    uint256 amountClaimable = claimables[j];

                    if (amountClaimable > 0) {
                        claimableRent[counter] = RentData(tnft, tokenIdLibrary[tnft][j], amountClaimable);
                        unchecked {
                            ++counter;
                        }
                    }
                    unchecked {
                        ++j;
                    }
                }
                unchecked {
                    ++i;
                }
            }

            // start iterating through the master claimable rent array claiming rent for each token.
            uint256 index;
            while (_withdrawAmount > primaryRentToken.balanceOf(address(this)) && index < counter) {

                IRentManager rentManager = _getRentManager(claimableRent[index].tnft);
                uint256 tokenId = claimableRent[index].tokenId;

                if (rentManager.claimableRentForToken(tokenId) > 0) {

                    uint256 preBal = primaryRentToken.balanceOf(address(this));
                    uint256 claimedRent = rentManager.claimRentForToken(tokenId);

                    require(primaryRentToken.balanceOf(address(this)) == (preBal + claimedRent), "claiming error");
                }

                unchecked {
                    ++index;
                }
            }
        }

        // transfer rent to msg.sender (factory owner)
        assert(primaryRentToken.transfer(_recipient, _withdrawAmount));
        totalRentValue -= _withdrawAmount;
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @return totalRent -> Amount of claimable rent by from all TNFTs in this basket + rent in basket balance.
     */
    function _getRentBal() internal view returns (uint256 totalRent) {
        // iterate through all supported tnfts and tokenIds deposited for each tnft.
        for (uint256 i; i < tnftsSupported.length;) {
            address tnft = tnftsSupported[i];

            uint256 claimable = _getRentManager(tnft).claimableRentForTokenBatchTotal(tokenIdLibrary[tnft]);

            if (claimable > 0) {
                totalRent += claimable;
            }

            unchecked {
                ++i;
            }
        }

        totalRent += primaryRentToken.balanceOf(address(this));
    }

    /**
     * @notice View method used to calculate amount of shares required given the usdValue of the TNFT and amount of rent needed.
     * @dev If primaryRentToken.decimals != 6, this func will fail.
     * @param usdValue $USD value of token being quoted.
     */
    function _quoteShares(uint256 usdValue) internal view returns (uint256 shares) {
        if (totalSupply() == 0) {
            shares = usdValue;
        } else {
            shares = ((usdValue * totalSupply()) / getTotalValueOfBasket());
        }
    }

    /**
     * @dev Get value of TNFT in native currency.
     * @param _tangibleNFT TNFT contract address of token.
     * @param _fingerprint fingerprint of token.
     * @return currency -> ISO code of native currency. (i.e. "GBP")
     * @return value -> Value of token in native currency.
     * @return decimals -> Amount of decimals used for precision.
     */
    function _getTnftNativeValue(address _tangibleNFT, uint256 _fingerprint) internal view returns (string memory currency, uint256 value, uint8 decimals) {
        IPriceOracle oracle = _getOracle(_tangibleNFT);

        uint256 currencyNum;
        (value, currencyNum) = oracle.marketPriceNativeCurrency(_fingerprint);

        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(factory()).currencyFeed());
        currency = currencyFeed.ISOcurrencyNumToCode(uint16(currencyNum));

        decimals = oracle.decimals();
    }

    /**
     * @dev Get $USD Value of specified token.
     * @param _tangibleNFT TNFT contract address.
     * @param _tokenId TokenId of token.
     * @return $USD value of token, note: base 1e18
     */
    function _getUSDValue(address _tangibleNFT, uint256 _tokenId) internal view returns (uint256) {
        (string memory currency, uint256 amount, uint8 nativeDecimals) = _getTnftNativeValue(
            _tangibleNFT, ITangibleNFT(_tangibleNFT).tokensFingerprint(_tokenId)
        );
        (uint256 price, uint256 priceDecimals) = _getUsdExchangeRate(currency);
        return (price * amount * 10 ** 18) / 10 ** priceDecimals / 10 ** nativeDecimals;
    }

    /**
     * @dev Get USD Price of given currency from ChainLink.
     * @param _currency Currency ISO code.
     * @return exchange rate.
     * @return decimals used for precision on priceFeed.
     */
    function _getUsdExchangeRate(string memory _currency) internal view returns (uint256, uint256) {
        ICurrencyFeedV2 currencyFeed = ICurrencyFeedV2(IFactory(factory()).currencyFeed());
        AggregatorV3Interface priceFeed = currencyFeed.currencyPriceFeeds(_currency);
        
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price < 0) price = 0;

        return (uint256(price), priceFeed.decimals());
    }

    /**
     * @notice This method is an internal view method that fetches the RentManager contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the RentManager for.
     * @return RentManager contract reference.
     */
    function _getRentManager(address _tangibleNFT) internal view returns (IRentManager) {
        return IFactory(factory()).rentManager(ITangibleNFT(_tangibleNFT));
    }

    /**
     * @notice This method is an internal view method that fetches the PriceOracle contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the PriceOracle for.
     * @return PriceOracle contract reference.
     */
    function _getOracle(address _tangibleNFT) internal view returns (IPriceOracle) {
        ITangiblePriceManager priceManager = IFactory(factory()).priceManager();
        return ITangiblePriceManager(address(priceManager)).oracleForCategory(ITangibleNFT(_tangibleNFT));
    }

    /**
     * @notice This method is an internal view method that fetches the RWAPriceNotificationDispatcher contract for a specified TNFT contract.
     * @param _tangibleNFT TNFT contract address we want the RWAPriceNotificationDispatcher for.
     * @return RWAPriceNotificationDispatcher contract reference.
     */
    function _getNotificationDispatcher(address _tangibleNFT) internal returns (IRWAPriceNotificationDispatcher) {
        return IGetNotificationDispatcher(address(_getOracle(_tangibleNFT))).notificationDispatcher();
    }

    /**
     * @notice Internal method for returning the address of BasketsVrfConsumer contract.
     * @return Address of BasketsVrfConsumer.
     */
    function _getBasketVrfConsumer() internal returns (address) {
        return IBasketManager(IFactory(factory()).basketsManager()).basketsVrfConsumer();
    }

    /**
     * @notice Internal method for returning the address of RevenueShare contract.
     * @return Address of RevenueShare.
     */
    function _getRevenueShare() internal returns (address) {
        return IBasketManager(IFactory(factory()).basketsManager()).revenueShare();
    }

    /**
     * @notice This helper method returns whether a provided TNFT token exists in the depositedTnfts array and if so, where in the array.
     * @param _tnft contract address.
     * @param _tokenId TokenId of token being fetched.
     * @return index -> Where in the `depositedTnfts` array the specified token resides.
     * @return exists -> If token exists in `depositedTnfts`, will be true. Otherwise false.
     */
    function _isDepositedTnft(address _tnft, uint256 _tokenId) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < depositedTnfts.length;) {
            if (depositedTnfts[i].tokenId == _tokenId && depositedTnfts[i].tnft == _tnft) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }

    /**
     * @notice This method returns whether a provided TNFT (category) address exists in the tnftsSupported array and if so, where in the array.
     * @param _tnft contract address.
     * @return index -> Where in the `tnftsSupported` array the specified contract address resides.
     * @return exists -> If address exists in `tnftsSupported`, will be true. Otherwise false.
     */
    function _isSupportedTnft(address _tnft) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < tnftsSupported.length;) {
            if (tnftsSupported[i] == _tnft) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }

    /**
     * @notice This method returns whether a provided tokenId exists in the tokenIdLibrary mapped array and if so, where in the array.
     * @param _tnft contract address.
     * @param _tokenId TokenId of token being fetched.
     * @return index -> Where in the `tokenIdLibrary` mapped array the specified token resides.
     * @return exists -> If token exists in `tokenIdLibrary`, will be true. Otherwise false.
     */
    function _isTokenIdLibrary(address _tnft, uint256 _tokenId) internal view returns (uint256 index, bool exists) {
        for(uint256 i; i < tokenIdLibrary[_tnft].length;) {
            if (tokenIdLibrary[_tnft][i] == _tokenId) return (i, true);
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }

}