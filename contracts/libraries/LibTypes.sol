// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "../Types.sol";

library LibTypes {	
	error BadProviderInfo();
	error BadSubscriberInfo();

	/**
	* Provider
	*       248       120                88        0
	* +--------+---------+-----------------+--------+
	* | active | balance | subscriberCount | unused |
	* +--------+---------+-----------------+--------+
	*/
	bytes32 constant PROVIDER_FORBIDDEN_BITS = bytes32(uint256(0xffffffffffffffffffffff));

	function getProviderSubscriberCount(
		bytes32 _pInfo
	) internal pure returns (uint32 subscriberCount) {
		subscriberCount = uint32((uint256(_pInfo) >> 88));
	}

	function getProviderBalance(
		bytes32 _pInfo
	) internal pure returns (uint128 balance) {
		balance = uint128((uint256(_pInfo) >> 120));
	}

	function getProviderActive(
		bytes32 _pInfo
	) internal pure returns (bool active) {
		active = uint8((uint256(_pInfo) >> 248)) > 0;
	}

	function decodeProvider(
		bytes32 _pInfo
	) internal pure returns (Provider memory decoded) {
		if ((_pInfo & PROVIDER_FORBIDDEN_BITS) > 0) revert BadProviderInfo();
		
		decoded.subscriberCount = uint32((uint256(_pInfo) >> 88));
		decoded.balance = uint128((uint256(_pInfo) >> 120));
		decoded.active = uint8((uint256(_pInfo) >> 248)) > 0;
	}

	function encodeProvider(
		Provider memory _provider
	) internal pure returns (bytes32 encoded) {
		uint8 activeUint8 = _provider.active ? 1 : 0;		
		encoded = bytes32(
			(uint256(_provider.subscriberCount) << 88) |
			(uint256(_provider.balance) << 120) |
			(uint256(activeUint8)<< 248)
		);
	}

	/**
	* Subscriber
	*       248       120     112        0
	* +--------+---------+------+--------+
	* | paused | balance | plan | unused |
	* +--------+---------+------+--------+
	*/

	bytes32 constant SUBSCRIBER_FORBIDDEN_BITS = bytes32(uint256(0xffffffffffffffffffffffffffff));

	function getSubscriberPlan(
		bytes32 _sInfo
	) internal pure returns (SubscriptionPlan plan) {
		plan = SubscriptionPlan(uint8((uint256(_sInfo) >> 112)));
	}

	function getSubscriberBalance(
		bytes32 _sInfo
	) internal pure returns (uint128 balance) {
		balance = uint128((uint256(_sInfo) >> 120));
	}

	function getSubscriberPaused(
		bytes32 _sInfo
	) internal pure returns (bool paused) {
		paused = uint8((uint256(_sInfo) >> 248)) > 0;
	}

	function decodeSubscriber(
		bytes32 _sInfo
	) internal pure returns (Subscriber memory decoded) {
		if ((_sInfo & SUBSCRIBER_FORBIDDEN_BITS) > 0) revert BadSubscriberInfo();

		decoded.plan = uint8((uint256(_sInfo) >> 112));
		decoded.balance = uint128((uint256(_sInfo) >> 120));
		decoded.paused = uint8((uint256(_sInfo) >> 248)) > 0;
	}

	function encodeSubscriber(
		Subscriber memory _subscriber
	) internal pure returns (bytes32 encoded) {
		uint8 pausedUint8 = _subscriber.paused ? 1 : 0;
		encoded = bytes32(
			(uint256(_subscriber.plan) << 112) |
			(uint256(_subscriber.balance) << 120) |
			(uint256(pausedUint8) << 248)
		);
	}
}