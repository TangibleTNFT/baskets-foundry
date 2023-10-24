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

// local imports
import { IBasket } from "./interfaces/IBasket.sol";
import { IBasketManager } from "./interfaces/IBasketsManager.sol";
import { IBasketsVrfConsumer } from "./interfaces/IBasketsVrfConsumer.sol";
import { IGetNotificationDispatcher } from "./interfaces/IGetNotificationDispatcher.sol";
import { RebaseTokenUpgradeable } from "./abstract/RebaseTokenUpgradeable.sol";


/**
 * @title Basket
 * @author Chase Brown
 * @notice ERC-20 token that represents a basket of ERC-721 TangibleNFTs that are categorized into "baskets".
 */
contract Basket is Initializable, RebaseTokenUpgradeable, IBasket, IRWAPriceNotificationReceiver, ReentrancyGuardUpgradeable, FactoryModifiers {

    // ~ State Variables ~

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
    uint256 public depositFee; // 0.5% by default

    uint256 public inCounter;

    uint256 public outCounter;

    /// @notice TangibleNFT contract => tokenId => InCounterId.
    //mapping(address => mapping(uint256 => uint256)) public fifoTracker;

    mapping(uint256 => TokenData) public fifoTracker;

    /// @notice This stores a reference to the primary ERC-20 token used for paying out rent.
    IERC20Metadata public primaryRentToken;

    /// @notice Address of basket creator.
    address public deployer;

    /// @notice Used to save slots for potential extra state variables later on.
    uint256[20] private __gap;


    // ~ Events ~

    /**
     * @notice This event is emitted when a TNFT is deposited into this basket.
     * @param prevOwner Previous owner before deposit. Aka depositor.
     * @param tnft TNFT contract address of token being deposited.
     * @param tokenId TokenId identifier of token being deposited.
     */
    event TNFTDeposited(address prevOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when a TNFT is redeemed from this basket.
     * @param newOwner New owner before deposit. Aka redeemer.
     * @param tnft TNFT contract address of token being redeemed.
     * @param tokenId TokenId identifier of token being redeemed.
     */
    event TNFTRedeemed(address newOwner, address indexed tnft, uint256 indexed tokenId);

    /**
     * @notice This event is emitted when the price of a TNFT token is updated by the oracle.
     * @param tnft TNFT contract address of token being updated.
     * @param tokenId TokenId identifier of token being updated.
     * @param oldPrice Old USD price of TNFT token.
     * @param newPrice New USD price of TNFT token.
     */
    event PriceNotificationReceived(address indexed tnft, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);

    // NOTE: FOR TESTING ONLY
    event Debug(string, uint256);


    // ~ Constructor ~

    constructor() {
        _disableInitializers();
    }


    // ~ Initializer ~

    /**
     * @notice Initializes Basket contract.
     * @param _name Unique name of basket contract.
     * @param _symbol Unique symbol of basket contract.
     * @param _factoryProvider FactoryProvider contract address.
     * @param _tnftType TNFT Type (category).
     * @param _rentToken ERC-20 token being used for rent. USDC by default.
     * @param _features Array of features TNFTs must support to be in this basket.
     * @param _deployer Address of creator of the basket contract.
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

        depositFee = 50; // 0.5%

        __RebaseToken_init(_name, _symbol);
        __FactoryModifiers_init(_factoryProvider);

        _setRebaseIndex(1 ether);

        tnftType = _tnftType;
        deployer = _deployer;

        primaryRentToken = IERC20Metadata(_rentToken);
    }

    
    // ~ External Methods ~

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
     * @notice This method is used to redeem a TNFT token. This method will take a budget of basket tokens and chooses
     *         the lowest rent yielding TNFT token in that specified budget range to transfer to redeemer.
     * @dev Burns basket tokens 1-1 with usdValue of token redeemed.
     * @param _budget Amount of basket tokens being submitted to redeem method.
     */
    function redeemTNFT(uint256 _budget) external { // TODO: Replace with FIFO method
        _redeemTNFT(msg.sender, _budget);
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
     * @notice This onlyFactoryOwner method allows a factory owner to withdraw a specified amount of claimable rent from this basket.
     * @param _withdrawAmount Amount of rent to withdraw. note: Should input decimals from `primaryRentToken.decimals()`. Default is 6.
     */
    function withdrawRent(uint256 _withdrawAmount) external onlyFactoryOwner {
        require((_getRentBal() / 10**12) >= _withdrawAmount, "Amount exceeds withdrawable rent");

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
        assert(primaryRentToken.transfer(msg.sender, _withdrawAmount));
    }

    /**
     * @notice This method is used to quote an amount of basket tokens transferred to depositor if a specfiied token is deposted.
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
        shares = _quoteShares(usdValue, 0);
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
        require(usdValue > 0, "Unsupported TNFT");

        // Get shares required
        sharesRequired = _quoteShares(usdValue, 0);
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @dev Returns an amount in USD (stablecoin) with 18 decimal points.
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

    
    // ~ Public Methods ~

    function rebase() public {
        // a. update rent
        // b. calculate new basket token price based off new rent amount -> update multiplier that calculated balanceOf
        // c. skim pools
        // d. wrap extra skimmed tokens from pool
        // e. use wrapped tokens for auto-bribe

        // rebase - v1
        //uint256 previousRentalIncome = totalRentValue;
        //uint256 totalRentalIncome = _getRentBal();
        //uint256 generatedRentalIncome = totalRentalIncome - previousRentalIncome;
        //uint256 currentTotalSupply = totalSupply();
        //uint256 newTotalSupply = currentTotalSupply + generatedRentalIncome;

        // rebase - v2
        //uint256 basketValue = getBasketValue() // total value in usd (including RE and collected rent, excluding vested rent)

        uint256 previousRentalIncome = totalRentValue;
        uint256 totalRentalIncome = _getRentBal();
        uint256 generatedRentalIncome = totalRentalIncome - previousRentalIncome;

        uint256 collectedRent = totalRentalIncome - previousRentalIncome;
        uint256 rebaseIndexDelta = collectedRent * 1e18 / getTotalValueOfBasket();

        uint256 rebaseIndex = rebaseIndex();

        rebaseIndex += rebaseIndexDelta;

        //uint256 rebaseIndex = newTotalSupply.mulDiv(1 ether, currentTotalSupply);

        totalRentValue = totalRentalIncome;
        _setRebaseIndex(rebaseIndex);
    }

    /**
     * @notice TODO UPDATE
     * @return redeemable -> RedeemData object containing all the data for token to be redeemed
     */
    function calculateFifo() public view returns (RedeemData memory redeemable) {
        // a. Locate tnft in array with correct fifo counter var
        uint256 fifoNum = outCounter + 1;
        TokenData memory token = fifoTracker[fifoNum];

        // b. if budget suffices, return token
        uint256 usdValue = valueTracker[token.tnft][token.tokenId];
        uint256 sharesRequired = _quoteShares(usdValue, 0);

        return RedeemData(token.tnft, token.tokenId, usdValue, sharesRequired);
    }

    // /**
    //  * @notice This function returns a list of TNFTs that could be potentially redeemed for a budget of basket tokens.
    //  * @param _budget Amount of basket tokens willing to burn for a redeemable TNFT token from within the basket.
    //  * @return inBudget -> Array of type RedeemData of all TNFT tokens that can be redeemed for the specified budget of basket tokens.
    //  * @return quantity -> Amount of tokens that can be redeemed for `_budget`. note: quantity == inBudget.length
    //  * @return valid -> If there are tokens that can be redeemed for `_budget`, valid will be true. Otherwise, false.
    //  */
    // function checkBudget(uint256 _budget) public view returns (RedeemData[] memory inBudget, uint256 quantity, bool valid) {
    //     uint256 len = depositedTnfts.length;
    //     inBudget = new RedeemData[](len);

    //     for (uint256 i; i < len;) {

    //         // get usd value of TNFT token
    //         uint256 usdValue = valueTracker[depositedTnfts[i].tnft][depositedTnfts[i].tokenId];
    //         // Calculate amount of basket tokens needed. Usd value of NFT + rent amount / share price == total basket tokens.
    //         uint256 sharesRequired = _quoteShares(usdValue, 0);

    //         if (_budget >= sharesRequired) {
    //             inBudget[quantity] = 
    //                 RedeemData(
    //                     depositedTnfts[i].tnft,
    //                     depositedTnfts[i].tokenId,
    //                     usdValue,
    //                     sharesRequired
    //                 );
    //             unchecked {
    //                 ++quantity;
    //             }
    //         }

    //         unchecked {
    //             ++i;
    //         }
    //     }

    //     quantity > 0 ? valid = true : valid = false;
    // }

    /**
     * @notice Return the USD value of share token for underlying assets, 18 decimals
     * @dev Underyling assets = TNFT + Accrued revenue
     */
    function getSharePrice() public view returns (uint256 sharePrice) { // TODO: Remove? not used
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
        unchecked {
            totalValue += totalNftValue;
            // get value of rent accrued by this contract
            totalValue += _getRentBal(); // TODO: Repalace with `totalValue += totalRentValue`
        }
    }

    /**
     * @notice This view method returns true if a specified token contains the features needed to be deposited into this basket.
     */
    function isCompatibleTnft(address _tangibleNFT, uint256 _tokenId) public view returns (bool) {
        if (ITangibleNFTExt(_tangibleNFT).tnftType() != tnftType) return false;

        uint256 length = supportedFeatures.length;
        if(length > 0) {
            for (uint256 i; i < length;) {

                ITangibleNFT.FeatureInfo memory featureData = ITangibleNFTExt(_tangibleNFT).tokenFeatureAdded(_tokenId, supportedFeatures[i]);
                if (!featureData.added) return false;

                unchecked {
                    ++i;
                }
            }
        }

        return true;
    }

    
    // ~ Internal Methods ~

    /**
     * @notice This internal method is used to deposit a specified TNFT from a depositor address to this basket.
     *         The deposit will be minted a sufficient amount of basket tokens in return.
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

        // update contract
        tokenDeposited[_tangibleNFT][_tokenId] = true;
        valueTracker[_tangibleNFT][_tokenId] = usdValue;

        depositedTnfts.push(TokenData(_tangibleNFT, _tokenId, fingerprint));
        tokenIdLibrary[_tangibleNFT].push(_tokenId);

        (, bool exists) = _isSupportedTnft(_tangibleNFT);
        if (!exists) {
            tnftsSupported.push(_tangibleNFT);
        }

        //fifoTracker[_tangibleNFT][_tokenId] = ++inCounter; // TODO: Test

        fifoTracker[++inCounter] = TokenData(_tangibleNFT, _tokenId, fingerprint);

        // take token from depositor
        IERC721(_tangibleNFT).safeTransferFrom(msg.sender, address(this), _tokenId);
        
        // register for price notifications
        IRWAPriceNotificationDispatcher notificationDispatcher = _getNotificationDispatcher(_tangibleNFT);

        require(INotificationWhitelister(address(notificationDispatcher)).whitelistedReceiver(address(this)), "Basket not WL on ND");
        INotificationWhitelister(address(notificationDispatcher)).registerForNotification(_tokenId);

        // Claim rent from tnft::rentManager and keep it in this contract TODO TEST
        uint256 preBal = primaryRentToken.balanceOf(address(this));

        // claim rent for TNFT being redeemed.
        uint256 receivedRent;
        IRentManager rentManager = _getRentManager(_tangibleNFT);

        if (rentManager.claimableRentForToken(_tokenId) > 0) {
            unchecked {
                receivedRent += rentManager.claimRentForToken(_tokenId);
            }
        }

        // verify claimed balance
        require(primaryRentToken.balanceOf(address(this)) == (preBal + receivedRent), "claiming error");

        // TODO: REBASE HERE

        // calculate shares for depositor
        basketShare = _quoteShares(usdValue, receivedRent);

        // if msg.sender is basketManager, it's making an initial deposit -> receiver of basket tokens needs to be deployer.
        if (msg.sender == IFactory(factory()).basketsManager()) {
            _depositor = deployer;
        }
        else {
            // if deposit isn't initial deposit from deployer (which will be most cases), charge a deposit fee.
            uint256 feeShare = (basketShare * depositFee) / 100_00; // TODO: Verify implementation & test
            basketShare -= feeShare;
        }

        // mint basket tokens to user
        _mint(_depositor, basketShare);

        // Update total nft value in this contract
        unchecked {
            totalNftValue += usdValue;
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
        RedeemData memory redeemable = calculateFifo();

        address _tangibleNFT = redeemable.tnft;
        uint256 _tokenId = redeemable.tokenId;
        uint256 _usdValue = redeemable.usdValue;
        uint256 _sharesRequired = redeemable.sharesRequired;

        require(balanceOf(_redeemer) >= _budget, "Insufficient balance");
        require(_budget >= _sharesRequired, "Insufficient budget");

        require(tokenDeposited[_tangibleNFT][_tokenId], "Invalid token");

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

        // TODO: REBASE HERE (change order)

        totalNftValue -= _usdValue;
        _burn(_redeemer, _sharesRequired);
        
        ++outCounter; // TODO: Test

        emit TNFTRedeemed(_redeemer, _tangibleNFT, _tokenId);
    }

    /**
     * @notice This method returns the unclaimed rent balance of all TNFTs inside the basket.
     * @dev Returns an amount in USD (stablecoin) with 18 decimal points.
     * @return totalRent -> Amount of claimable rent by from all TNFTs in this basket + rent in basket balance.
     */
    function _getRentBal() internal view returns (uint256 totalRent) {
        uint256 decimals = decimals() - IERC20Metadata(primaryRentToken).decimals();

        // iterate through all supported tnfts and tokenIds deposited for each tnft.
        for (uint256 i; i < tnftsSupported.length;) {
            address tnft = tnftsSupported[i];

            uint256 claimable = _getRentManager(tnft).claimableRentForTokenBatchTotal(tokenIdLibrary[tnft]);

            if (claimable > 0) {
                decimals > 0 ?
                    totalRent += claimable * 10**decimals :
                    totalRent += claimable;
            }

            unchecked {
                ++i;
            }
        }

        decimals > 0 ?
            totalRent += primaryRentToken.balanceOf(address(this)) * 10**decimals :
            totalRent += primaryRentToken.balanceOf(address(this));
    }

    /**
     * @notice View method used to calculate amount of shares required given the usdValue of the TNFT and amount of rent needed.
     * @dev If primaryRentToken.decimals != 6, this func will fail.
     * @param usdValue $USD value of token being quoted.
     * @param amountRent If rent is being counted in minting, count rent towards quote. note: only used during deposit.
     */
    function _quoteShares(uint256 usdValue, uint256 amountRent) internal view returns (uint256 shares) {
        uint256 combinedValue = (usdValue + (amountRent * 10**12));

        if (totalSupply() == 0) {
            shares = combinedValue;
        } else {
            shares = ((combinedValue * totalSupply()) / getTotalValueOfBasket());
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
