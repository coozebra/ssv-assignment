// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Errors} from "./interfaces/Errors.sol";
import "./libraries/LibTypes.sol";

contract ProviderController is Ownable, Errors, ERC721 {
    using SafeERC20 for IERC20;
    using LibTypes for bytes32;

    uint256 public constant UINT128_MAX = type(uint128).max;
    uint256 public constant ROLLOVER_INTERVAL = 31 days;

    uint256 public providerId;
    uint256 public subscriberId = UINT128_MAX;

    IERC20 public immutable token;
    uint256 public immutable serviceFeeMinimum;

    uint256 public lastRolloverTimestamp;    

    // mapping
    mapping(uint256 => bytes32) providers;
    mapping(uint256 => uint128) providerFees;
    mapping(bytes32 => bool) providerRegKeys;
    mapping(uint256 => bytes32) subscribers;

    // subscriber -> list of providers
    // 3<= value array's length <= 14
    mapping(uint256 => uint256[]) subscriberProviders;

    // Events
    event ProviderAdded(uint256 indexed providerId, address indexed owner, bytes publicKey, uint128 fee);
    event ProviderRemoved(uint256 indexed providerId);
    event SubscriberAdded(uint256 indexed subscriberId, address indexed owner, SubscriptionPlan plan, uint128 deposit);
    event SubscriberPaused(uint256 indexed subscriberId);
    event SubscriberDeposited(uint256 indexed subscriberId, uint128 deposit);
    event RolloverExecuted(uint256 timestamp);
    event ProviderFeeUpdated(uint256 _providerId, uint128 _fee);
    event ProviderStateUpdated(uint256[] _providers, bool[] _states);
    event ProviderEarningWithdrawn(uint256 _providerId, uint128 _earning);

    // Modifiers
    modifier onlyPXSOwner(uint256 _id) {
        if (super._ownerOf(_id) != msg.sender) revert CallerNotAllowed();
        _;
    }

    modifier isProviderId(uint256 _id) {
        if (_id > UINT128_MAX) revert InvalidProviderId({_providerId: _id});
        _;
    }

    modifier isSubscriberId(uint256 _id) {
        if (_id <= UINT128_MAX) revert InvalidSubscriberId({_subscriberId: _id});
        _;
    }

    constructor(
        address _token,
        uint256 _serviceFeeMinimum
    ) ERC721("ProviderXSubscriber", "PXS") {
        if (_token == address(0)) revert ZeroAddress();

        token = IERC20(_token);
        serviceFeeMinimum = _serviceFeeMinimum;
    }

    function registerProvider(
        bytes calldata _registerKey, 
        uint128 _fee
    ) external {
        // fee (token units) should be greater than a fixed value. Add a check
        if (_fee < serviceFeeMinimum) revert InsufficientServiceFee();

        // the system doesn't allow to register a provider with the same registerKey.
        // Implement a way to prevent it.
        bytes32 hash = keccak256(abi.encodePacked(
            msg.sender,
            _registerKey
        ));
        if (providerRegKeys[hash]) revert DuplicateProviderRegKey();
        providerRegKeys[hash] = true;
        
        // check UINT128_MAX is not reached
        uint256 id = ++providerId;
        if (id > UINT128_MAX) revert ProviderFull();

        providers[id] = LibTypes.encodeProvider(
            Provider({
                subscriberCount: 0,
                balance: 0,
                active: true
            })
        );

        providerFees[id] = _fee;

        super._mint(msg.sender, id);
        emit ProviderAdded(id, msg.sender, _registerKey, _fee);
    }

    function removeProvider(
        uint256 _providerId
    ) external isProviderId(_providerId) onlyPXSOwner(_providerId) {
        uint128 balance = providers[_providerId].getProviderBalance();

        delete providers[_providerId];

        token.safeTransfer(msg.sender, balance);

        super._burn(_providerId);
        emit ProviderRemoved(_providerId);
    }

    function resgisterSubscriber(
        uint128 _deposit, 
        SubscriptionPlan _plan, 
        uint256[] calldata _providerIds
    ) external {
        // Only allow subscriber registrations if providers are active
        // Provider list must at least 3 and less or equals 14
        // check if the deposit amount cover expenses of providers' fees for at least 2 months
        // plan does not affect the cost of the subscription

        uint256 id = ++subscriberId;
        uint256 depositMinimum;

        if (_providerIds.length < 3 || _providerIds.length > 14) revert InvalidProviderIdsArray();

        for (uint8 i = 0; i < _providerIds.length; i++) {
            uint256 pId = _providerIds[i];
            bytes32 pInfo = providers[pId];
            Provider memory p = pInfo.decodeProvider();

            if (!p.active) revert InactiveProvider({_providerId: pId});

            // should cover 2 month fee
            depositMinimum += 2 * providerFees[pId];

            // increase subscriber count by 1
            p.subscriberCount++;

            providers[pId] = LibTypes.encodeProvider(p);
        }

        if (_deposit < depositMinimum) revert InsufficientSubscriberRegDeposit();

        subscribers[id] = LibTypes.encodeSubscriber(
            Subscriber({
                balance: _deposit, 
                plan: uint8(_plan), 
                paused: false
            })
        );

        // deposit the funds
        token.safeTransferFrom(msg.sender, address(this), _deposit);

        super._mint(msg.sender, id);
        emit SubscriberAdded(id, msg.sender, _plan, _deposit);
    }

    function pauseSubscription(
        uint256 _subscriberId
    ) external isSubscriberId(_subscriberId) onlyPXSOwner(_subscriberId) {
        // pause
        Subscriber memory s = subscribers[_subscriberId].decodeSubscriber();
        
        if (s.paused) revert SubscriberAlreadyPaused();
        s.paused = true;

        subscribers[_subscriberId] = LibTypes.encodeSubscriber(s);

        // reduce subscriberCount by 1 for every provider
        {
            uint256[] memory pIds = subscriberProviders[_subscriberId];

            // length is between 3 and 14
            for (uint8 i = 0; i < pIds.length; i++) {
                uint256 pId = pIds[i];
                Provider memory p = providers[pId].decodeProvider();

                if (super._exists(pId)) {
                    if (p.subscriberCount == 0) revert PXSConflict({
                        _providerId: pId,
                        _subscriberId: _subscriberId
                    });
                    
                    // decrease subscriberCount
                    p.subscriberCount--;

                    providers[pId] = LibTypes.encodeProvider(p);
                }
            }            
        }
        
        emit SubscriberPaused(_subscriberId);
    }

    function deposit(
        uint256 _subscriberId, 
        uint128 _deposit
    ) external isSubscriberId(_subscriberId) onlyPXSOwner(_subscriberId) {
        token.transferFrom(msg.sender, address(this), _deposit);
        Subscriber memory s = subscribers[_subscriberId].decodeSubscriber();
        s.balance += _deposit;
        subscribers[_subscriberId] = LibTypes.encodeSubscriber(s);
        emit SubscriberDeposited(_subscriberId, _deposit);
    }

    function withdrawProviderEarnings(
        uint256 _providerId
    ) external isProviderId(_providerId) onlyPXSOwner(_providerId) {
        Provider memory p = providers[_providerId].decodeProvider();
        uint128 balance = p.balance;
        token.safeTransfer(msg.sender, balance);

        p.balance = 0;
        providers[_providerId] = LibTypes.encodeProvider(p);
        emit ProviderEarningWithdrawn(_providerId, balance);
    }

    function updateProvidersState(
        uint256[] calldata _providerIds,
        bool[] calldata _states
    ) external onlyOwner {
        if (_providerIds.length != _states.length) revert ArrayLengthMismatch();

        for (uint8 i = 0; i < _providerIds.length; i++) {
            uint256 pId = _providerIds[i];

            if (pId > UINT128_MAX) revert InvalidProviderId({_providerId: pId});
            if (super._exists(pId)) {
                Provider memory p = providers[pId].decodeProvider();
                p.active = _states[i];
                providers[pId] = LibTypes.encodeProvider(p);
            }
        }

        emit ProviderStateUpdated(_providerIds, _states);
    }

    /// @notice Can be called by any wallet
    function rollover() external {
        if (lastRolloverTimestamp + ROLLOVER_INTERVAL > block.timestamp) revert TooEarly();

        uint128 balanceMinimum;
        uint256 pId;
        bool sBalanceIsSufficient;
        Provider memory p;
        Subscriber memory s;

        for (uint256 sId = UINT128_MAX + 1; sId <= subscriberId; sId++) {
            s = subscribers[sId].decodeSubscriber();

            if (!s.paused) {
                balanceMinimum = 0;
                uint256[] memory pIds = subscriberProviders[sId]; 
                
                // every subscriber has equal/less than 14 providers
                for (uint8 j = 0; j < pIds.length; j++) {
                    pId = pIds[j];
                    
                    if (super._exists(pId)) {
                        balanceMinimum += providerFees[pId];
                    }
                }

                // check if subscriber has sufficient funds
                sBalanceIsSufficient = s.balance >= balanceMinimum;

                // every subscriber has equal/less than 14 providers
                for (uint8 j = 0; j < pIds.length; j++) {
                    pId = pIds[j];
                    
                    if (super._exists(pId)) {
                        p = providers[pId].decodeProvider();

                        if (sBalanceIsSufficient) {
                            p.balance += providerFees[pId];
                        } else {
                            p.subscriberCount--;
                        }

                        providers[pId] = LibTypes.encodeProvider(p);
                    }
                }


                if (sBalanceIsSufficient) {
                    // deduct service fee
                    s.balance -= balanceMinimum;
                } else {
                    // force pause
                    s.paused = true;
                }

                subscribers[sId] = LibTypes.encodeSubscriber(s);
            }            
        }

        lastRolloverTimestamp = block.timestamp;
        emit RolloverExecuted(block.timestamp);
    }

    function updateProviderFee(
        uint256 _providerId,
        uint128 _fee
    ) external isProviderId(_providerId) onlyPXSOwner(_providerId) {
        if (_fee < serviceFeeMinimum) revert InsufficientServiceFee();

        providerFees[_providerId] = _fee;
        emit ProviderFeeUpdated(_providerId, _fee);
    }

    // view functions
    function getProviderState(
        uint256 _providerId
    ) public view returns (Provider memory) {
        return providers[_providerId].decodeProvider();
    }

    function getProviderEarnings(
        uint256 _providerId
    ) public view returns (uint128) {
        return providers[_providerId].getProviderBalance();
    }

    function getSubscriberState(
        uint256 _subscriberId
    ) public view returns (Subscriber memory) {
        return subscribers[_subscriberId].decodeSubscriber();
    }

    function getSubscriberBalance(
        uint256 _subscriberId
    ) public view returns (uint256) {
        return subscribers[_subscriberId].getSubscriberBalance();
    }

    // internal functions
    /// @notice Disable transfer
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256,
        uint256
    ) internal virtual override {
        if (_from != address(0) && _to != address(0)) revert TransferNotAllowed();
    }
}
