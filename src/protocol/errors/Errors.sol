// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*
 * YieldZero Protocol Errors
 * Centralized custom error definitions for all YieldZero contracts
 */

// ============================================================================
// VAULT ERRORS (YieldZeroVault)
// ============================================================================

error YZVault_Paused();
error YZVault_ZeroReceiver();
error YZVault_CallerNotComposer();
error YZVault_ZeroAmount();
error YZVault_ZeroShares();
error YZVault_InvalidAccessControl();
error YZVault_InvalidComposer();
error YZVault_PreviewMismatch();
error YZVault_InsufficientShares();
error YZVault_InsufficientAssets();
error YZVault_ZeroEmergencyAmount();
error YZAccessControl_CallerNotConfigManager();

// ============================================================================
// COMPOSER ERRORS (YieldZeroComposer)
// ============================================================================

error YZComposer_ZeroAmount();
error YZComposer_BelowMinimum();
error YZComposer_AboveMaximum();
error YZComposer_ZeroAddress();
error YZComposer_InvalidDestination();
error YZComposer_SlippageExceeded();
error YZComposer_RateLimited();
error YZComposer_InsufficientTVL();
error YZComposer_InsufficientBalance();
error YZComposer_InvalidAccessControl();
error YZComposer_CallerNotConfigManager();
error YZComposer_PreviewMismatch();
error YZComposer_TVLInvariantBroken();

// ============================================================================
// HUB ERRORS (YieldZeroHub)
// ============================================================================

error YZHub_InvalidVault();
error YZHub_InvalidComposer();
error YZHub_InvalidMessager();
error YZHub_MessagerNotConfigured();
error YZHub_Paused();
error YZHub_MaxSpokesExceeded();
error YZHub_InvalidSpoke();
error YZHub_SpokeAlreadyConnected();
error YZHub_SpokeNotConnected();
error YZHub_InvalidFeeBps();
error YZHub_InvalidFeeRecipient();
error YZHub_HarvestDisabled();
error YZHub_HarvestNotReady();
error YZHub_NoSpokesConnected();
error YZHub_CallerNotFeeRecipient();
error YZHub_NoFeesToWithdraw();
error YZHub_NativeTransferFailed();

// ============================================================================
// MESSAGER ERRORS (YieldZeroMessager)
// ============================================================================

error YZMessager_InvalidConstructorInputs();
error YZMessager_InvalidHub();
error YZMessager_InvalidEndpointId();
error YZMessager_InvalidPeerAddress();
error YZMessager_PeerNotConfigured();
error YZMessager_NotAuthorized();
error YZMessager_InvalidMessageType();
error YZMessager_InvalidFeeValue();

// ============================================================================
// READER ERRORS (YieldZeroReader)
// ============================================================================

error YZReader_InvalidAddress();

// ============================================================================
// RATE LIMITER ERRORS
// ============================================================================

error YZRateLimiter_OperationLimitExceeded();
error YZRateLimiter_InvalidLimit();

// ============================================================================
// ACCESS CONTROL ERRORS (YieldZeroAccessControl)
// ============================================================================

error YZAccessControl_CallerNotAdmin();
error YZAccessControl_ZeroAddress();
error YZAccessControl_RoleAlreadyGranted();
error YZAccessControl_RoleNotGranted();

