pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

contract Governornance {
    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes() public pure returns (uint) { return 40_000_000e18; } // 4% of ZKM

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public pure returns (uint) { return 10_000_000e18; } // 1% of ZKM

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint) { return 10; } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint) { return 1; } // 1 block

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure returns (uint) { return 40_320; } // ~7 days in blocks (assuming 15s blocks)

    /// @notice The address of the Zkam Protocol Timelock
    TimelockInterface public timelock;

    /// @notice The address of the Zkam governance token
    ZKMInterface public zkm;

    /// @notice The address of the Zkam Proxy governance token
    ProxyInterface public target;

    /// @notice The total number of proposals
    uint public proposalCount;

    struct Proposal {
        uint id;
        address proposer;
        uint eta;

        uint value;
        string signature;
        bytes calldatas;

        uint startBlock;
        uint endBlock;

        uint forVotes;
        uint againstVotes;

        bool canceled;
        bool executed;

        mapping (address => Receipt) receipts;
    }

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        bool hasVoted;
        bool support;
        uint256 votes;
    }

    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @notice The official record of all proposals ever proposed
    mapping (uint => Proposal) public proposals;

    /// @notice The latest proposal for each proposer
    mapping (address => uint) public latestProposalIds;

    /// @notice An event emitted when a new proposal is created
    event ProposalCreated(uint id, address proposer, address target, uint value, string signature, bytes calldatas, uint startBlock, uint endBlock);

    /// @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(address voter, uint proposalId, bool support, uint votes);

    /// @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint id);

    /// @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint id, uint eta);

    /// @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint id);

    constructor(address timelock_, address zkm_, address target_) public {
        timelock = TimelockInterface(timelock_);
        zkm = ZKMInterface(zkm_);
        target = ProxyInterface(target_);
    }

    function propose(uint value, string memory signature, bytes memory calldatas) public returns (uint) {
        require(zkm.getPriorVotes(msg.sender, sub256(block.number, 1)) > proposalThreshold());
      
        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active);
          require(proposersLatestProposalState != ProposalState.Pending);
        }

        uint startBlock = add256(block.number, votingDelay());
        uint endBlock = add256(startBlock, votingPeriod());

        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.value = value;
        newProposal.signature = signature;
        newProposal.startBlock = startBlock;
        newProposal.endBlock = endBlock;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.canceled = false;
        newProposal.executed = false;

        latestProposalIds[newProposal.proposer] = newProposal.id;

        emit ProposalCreated(newProposal.id, msg.sender, address(target), value, signature, calldatas, startBlock, endBlock);
        return newProposal.id;
    }

    function queue(uint proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded);
        Proposal storage proposal = proposals[proposalId];
        uint eta = add256(block.timestamp, timelock.delay());
        
        _queueOrRevert(address(target), proposal.value, proposal.signature, proposal.calldatas, eta);
        
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function _queueOrRevert(address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))));
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint proposalId) public payable {
        require(state(proposalId) == ProposalState.Queued);
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        
        timelock.executeTransaction{value: proposal.value}(address(target), proposal.value, proposal.signature, proposal.calldatas, proposal.eta);
        
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint proposalId) public {
        ProposalState state = state(proposalId);
        require(state != ProposalState.Executed);

        Proposal storage proposal = proposals[proposalId];
        require(zkm.getPriorVotes(proposal.proposer, sub256(block.number, 1)) < proposalThreshold());

        proposal.canceled = true;
        timelock.cancelTransaction(address(target), proposal.value, proposal.signature, proposal.calldatas, proposal.eta);

        emit ProposalCanceled(proposalId);
    }

    function getActions(uint proposalId) public view returns (address target, uint value, string memory signature, bytes memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (address(target), p.value, p.signature, p.calldatas);
    }

    function getReceipt(uint proposalId, address voter) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint proposalId, bool support) public {
        require(state(proposalId) == ProposalState.Active);
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[msg.sender];
        require(receipt.hasVoted == false);
        uint256 votes = zkm.getPriorVotes(msg.sender, proposal.startBlock);

        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(msg.sender, proposalId, support, votes);
    }

    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function getChainId() internal view returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}

interface TimelockInterface {
    function delay() external view returns (uint);
    function GRACE_PERIOD() external view returns (uint);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external returns (bytes32);
    function cancelTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external;
    function executeTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external payable returns (bytes memory);
}

interface ZKMInterface {
    function getPriorVotes(address account, uint blockNumber) external view returns (uint256);
}

interface ProxyInterface {
    function setTargetStatus(address target, bool status) external;

    function setFallbackStatus(address target, bool status) external;

    function setMethodStatus(address target, bytes4 selector, bool status) external;

    function setPredicate(address target, bytes4 selector, address predicate) external;
}