// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
/// @title TimelockHooks
/// @notice Time-delayed action hooks for the YieldZero Ops SDK.
/// 
/// This contract provides timelock functionality for sensitive operations
/// like changing adapters, updating TVL caps, or modifying rate limits.
/// Actions must be queued and wait for a delay period before execution.
contract TimelockHooks is AccessControl {
    /// Delay between queue and execution
    uint256 private _delay;
    
    /// Mapping of pending actions
    mapping(bytes32 => Proposal) private _proposals;
    
    /// Queue of action hashes
    bytes32[] private _queue;
    struct Proposal {
        address target;
        bytes data;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
        string description;
    }
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);
    event ProposalQueued(
        bytes32 indexed proposalId,
        address indexed target,
        uint256 executeAfter,
        string description
    );
    event ProposalExecuted(bytes32 indexed proposalId);
    event ProposalCancelled(bytes32 indexed proposalId);
    bytes32 public constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    modifier onlyTimelockAdmin() {
        require(hasRole(TIMELOCK_ADMIN_ROLE, msg.sender), "TimelockHooks: caller is not timelock admin");
        _;
    }
    modifier onlyProposer() {
        require(hasRole(PROPOSER_ROLE, msg.sender), "TimelockHooks: caller is not proposer");
        _;
    }
    modifier onlyExecutor() {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "TimelockHooks: caller is not executor");
        _;
    }
    /// @notice Constructor
    constructor(uint256 _delay, address _initialAdmin) {
        require(_initialAdmin != address(0), "TimelockHooks: zero address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(TIMELOCK_ADMIN_ROLE, _initialAdmin);
        _grantRole(PROPOSER_ROLE, _initialAdmin);
        _grantRole(EXECUTOR_ROLE, _initialAdmin);
        
        _delay = _delay;
    }
    /// @notice Update the delay period
    function updateDelay(uint256 _newDelay) external onlyTimelockAdmin {
        require(_newDelay >= 1 hours, "TimelockHooks: delay must be >= 1 hour");
        require(_newDelay <= 30 days, "TimelockHooks: delay must be <= 30 days");
        
        uint256 oldDelay = _delay;
        _delay = _newDelay;
        
        emit DelayUpdated(oldDelay, _newDelay);
    }
    /// @notice Queue a proposal for delayed execution
    /// @return proposalId The proposal ID
    function queueProposal(
        address _target,
        bytes calldata _data,
        string calldata _description
    ) external onlyProposer returns (bytes32 proposalId) {
        require(_target != address(0), "TimelockHooks: zero target");
        
        proposalId = keccak256(abi.encode(_target, _data, _description));
        
        /// Check not already queued
        require(_proposals[proposalId].executeAfter == 0, "TimelockHooks: proposal already queued");
        
        uint256 executeAfter = block.timestamp + _delay;
        
        _proposals[proposalId] = Proposal({
            target: _target,
            data: _data,
            executeAfter: executeAfter,
            executed: false,
            cancelled: false,
            description: _description
        });
        
        _queue.push(proposalId);
        
        emit ProposalQueued(proposalId, _target, executeAfter, _description);
    }
    /// @notice Execute a queued proposal
    function executeProposal(
        address _target,
        bytes calldata _data,
        string calldata _description
    ) external onlyExecutor returns (bytes memory) {
        bytes32 proposalId = keccak256(abi.encode(_target, _data, _description));
        
        Proposal storage proposal = _proposals[proposalId];
        
        require(proposal.executeAfter > 0, "TimelockHooks: proposal not found");
        require(!proposal.executed, "TimelockHooks: already executed");
        require(!proposal.cancelled, "TimelockHooks: cancelled");
        require(block.timestamp >= proposal.executeAfter, "TimelockHooks: not ready");
        
        /// Mark as executed
        proposal.executed = true;
        
        /// Execute the call
        (bool success, bytes memory returnData) = _target.call(_data);
        require(success, "TimelockHooks: execution failed");
        
        emit ProposalExecuted(proposalId);
        
        return returnData;
    }
    /// @notice Cancel a queued proposal
    function cancelProposal(bytes32 _proposalId) external onlyTimelockAdmin {
        Proposal storage proposal = _proposals[_proposalId];
        
        require(proposal.executeAfter > 0, "TimelockHooks: proposal not found");
        require(!proposal.executed, "TimelockHooks: already executed");
        require(!proposal.cancelled, "TimelockHooks: already cancelled");
        
        proposal.cancelled = true;
        
        emit ProposalCancelled(_proposalId);
    }
    /// @notice Get proposal details
    /// @return Proposal struct
    function getProposal(bytes32 _proposalId) external view returns (Proposal memory) {
        return _proposals[_proposalId];
    }
    /// @notice Get queue length
    /// @return Number of queued proposals
    function queueLength() external view returns (uint256) {
        return _queue.length;
    }
    /// @notice Get queued proposal IDs
    /// @return Array of proposal IDs
    function getQueue() external view returns (bytes32[] memory) {
        return _queue;
    }
    /// @notice Check if a proposal is pending
    /// @return True if proposal is pending
    function isProposalPending(bytes32 _proposalId) external view returns (bool) {
        return _proposals[_proposalId].executeAfter > 0 && 
               !_proposals[_proposalId].executed && 
               !_proposals[_proposalId].cancelled;
    }
    /// @notice Get the delay period
    /// @return Delay in seconds
    function delay() external view returns (uint256) {
        return _delay;
    }
}
