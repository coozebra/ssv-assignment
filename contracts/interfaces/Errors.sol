// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface Errors {
  error ZeroAddress();
  error InsufficientServiceFee();
  error DuplicateProviderRegKey();
  error ProviderFull();
  error CallerNotAllowed();
  error InactiveProvider(uint256 _providerId);
  error InvalidProviderIdsArray();
  error InsufficientSubscriberRegDeposit();
  error InvalidProviderId(uint256 _providerId);
  error InvalidSubscriberId(uint256 _subscriberId);
  error PXSConflict(uint256 _providerId, uint256 _subscriberId);
  error ArrayLengthMismatch();
  error TooEarly();
  error SubscriberAlreadyPaused();
  error TransferNotAllowed();
}