// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "src/IFireXp.sol";
import "forge-std/console.sol";

/**
 * @title ZharChallenges
 * @dev Decentralized challenge platform contract
 * Roles:
 * - 🔥 IGNITER: Creates challenges
 * - ⚔️ ZHARRIOR: Completes challenges  
 * - 🪵 STOKER: Stakes on challenges
 * - 🔮 ORACLE: Validates disputed challenges
 * Note: ✨ SPARK A.I. operates off-chain for safety and approval
 */
 
contract ZharChallenges is ReentrancyGuard, Ownable, Pausable {
    
    // ============ STATE VARIABLES ============

    IFireXp public immutable fireXPToken;
    IERC20 public immutable europToken;
    address public defiTreasury;
    address public tempOracleAddress; // Centralized oracle for now
    
    uint256 public constant ZHARRIOR_SHARE = 7000; // 70.00%
    uint256 public constant MAX_IGNITER_SHARE = 2000; // Max 20.00%
    uint256 public constant DEFI_SHARE = 500; // 5.00%
    uint256 public constant MAX_IGNITER_CAP = 2500 * 10**18; // €2,500 max
    uint256 public constant DISPUTE_THRESHOLD = 5000; // 50.00% needed to dispute
    uint256 public constant CONTEST_PERIOD = 2 days; // 2 days to contest disputes
    
    uint256 public challengeCounter;
    
    // ============ STRUCTS ============
    
    struct Creator {
        address creator;
        string name;
        string metadataUri;
        bool isActive;
        uint256 totalChallengesCompleted;
    }
    
    struct Challenge {
        uint256 challengeId;
        address forCreator; // Zharrior who will complete
        address igniter; // Who created the challenge
        string description;
        uint256 treasury; // Total staked amount
        uint256 createdAt;
        uint256 expiration;
        uint256 challengeCreatorReward; // Percentage for creator
        string proofUri;
        uint256 proofUpdatedAt;
        uint256 claimedAt;
        uint256 disputePeriod; // Time window for disputes after proof submission
        uint256 disputeContestDeadline; // Deadline for contesting disputes
        string contestReason; // Reason for contesting
        ChallengeStatus status;
        mapping(address => uint256) stakes; // Stoker stakes
        mapping(address => bool) disputes; // Track who disputed
        address[] stokers; // List of all stokers
        uint256 totalDisputeValue; // Total value of disputes
    }
    
    enum ChallengeStatus {
        Active,
        ProofSubmitted,
        ValidationByOracle,
        Completed,
        Expired,
        Failed
    }

    
    // ============ MAPPINGS ============
    
    mapping(address => Creator) public creators;
    mapping(uint256 => Challenge) public challenges;
    mapping(address => uint256[]) public userChallenges;
    
    // ============ EVENTS ============
    
    event CreatorRegistered(address indexed creator, string name, string metadataUri);
    event ChallengeCreated(uint256 indexed challengeId, address indexed igniter, address indexed forCreator,
     uint256 expiration, uint256 disputePeriod, string description, uint256 challengeCreatorReward);
    event ChallengeDepositIncrease(uint256 indexed challengeId, address indexed stoker, uint256 amount);
    event ProofSubmitted(uint256 indexed challengeId, string proofUri);
    event ProofDisputed(uint256 indexed challengeId, address indexed disputer, uint256 disputeValue, uint256 totalDisputeValue);
    event DisputesContested(uint256 indexed challengeId, address indexed challenger, string reason);
    event OracleValidation(uint256 indexed challengeId, address indexed oracle, bool approved, string reason);
    event ChallengeCompleted(uint256 indexed challengeId, uint256 zharriorReward, uint256 igniterReward, uint256 protocolReward);
    event ChallengeFailed(uint256 indexed challengeId, uint256 totalDisputeValue, uint256 treasuryValue);
    event ChallengeExpired(uint256 indexed challengeId);
    event FireXPAwarded(address indexed user, uint256 amount);
    event OracleAddressUpdated(address indexed oldOracle, address indexed newOracle);
    
    // ============ MODIFIERS ============
    
    modifier onlyRegisteredCreator() {
        require(creators[msg.sender].isActive, "Not a registered creator");
        _;
    }
    
    modifier challengeExists(uint256 _challengeId) {
        require(_challengeId <= challengeCounter && _challengeId > 0, "Challenge does not exist");
        _;
    }
    
    modifier challengeActive(uint256 _challengeId) {
        require(challenges[_challengeId].status == ChallengeStatus.Active, "Challenge not active");
        require(block.timestamp < challenges[_challengeId].expiration, "Challenge expired");
        _;
    }
    
    modifier onlyOracle() {
        require(msg.sender == tempOracleAddress, "Only oracle can call this function");
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address _fireXPToken,
        address _europToken,
        address _defiTreasury,
        address _tempOracleAddress,
        address _owner
    ) Ownable(_owner) {
        
        europToken = IERC20(_europToken);
        fireXPToken = IFireXp(_fireXPToken);
        defiTreasury = _defiTreasury;
        tempOracleAddress = _tempOracleAddress;
    }
    
    // ============ CREATOR FUNCTIONS ============
    
    /**
     * @dev Register a new creator (Zharrior)
     */
    function registerCreator(string memory _name, string memory _metadataUri) external {
        require(!creators[msg.sender].isActive, "Already registered");
        require(bytes(_name).length > 0, "Name cannot be empty");
        
        Creator storage newCreator = creators[msg.sender];
        newCreator.creator = msg.sender;
        newCreator.name = _name;
        newCreator.metadataUri = _metadataUri;
        newCreator.isActive = true;
        
        emit CreatorRegistered(msg.sender, _name, _metadataUri);
    }
    
    // ============ CHALLENGE FUNCTIONS ============
    
    /**
     * @dev Create a new challenge (Igniter function)
     */
    function createChallenge(
        address _forCreator,
        string memory _description,
        uint256 _expiration,
        uint256 _challengeCreatorReward,
        uint256 _disputePeriod
    ) external whenNotPaused returns (uint256) {
        require(creators[_forCreator].isActive, "Creator not registered");
        require(_expiration > block.timestamp + 36 hours, "Expiration must be at least 36 hours in future");
        require(_challengeCreatorReward <= 9000, "Invalid reward percentage"); // Max 90%
        // require(_disputePeriod >= 24 hours && _disputePeriod <= 7 days, "Invalid dispute period");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        challengeCounter++;
        Challenge storage newChallenge = challenges[challengeCounter];
        
        newChallenge.challengeId = challengeCounter;
        newChallenge.forCreator = _forCreator;
        newChallenge.igniter = msg.sender;
        newChallenge.description = _description;
        newChallenge.createdAt = block.timestamp;
        newChallenge.expiration = _expiration;
        newChallenge.challengeCreatorReward = _challengeCreatorReward;
        newChallenge.disputePeriod = _disputePeriod;
        newChallenge.status = ChallengeStatus.Active;
        
        userChallenges[msg.sender].push(challengeCounter);
        userChallenges[_forCreator].push(challengeCounter);
        
        emit ChallengeCreated(challengeCounter, msg.sender, _forCreator, _expiration, _disputePeriod,
        _description, _challengeCreatorReward);
        return challengeCounter;
    }
    
    /**
     * @dev Add stake to a challenge (Stoker function)
     */
    function depositToChallenge(uint256 _challengeId, uint256 _amount) 
        external 
        challengeExists(_challengeId) 
        challengeActive(_challengeId) 
        whenNotPaused 
    {
        require(_amount > 0, "Amount must be greater than 0");
        require(europToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        Challenge storage challenge = challenges[_challengeId];
        
        // Add to stokers list if first time staking
        if (challenge.stakes[msg.sender] == 0) {
            challenge.stokers.push(msg.sender);
        }
        
        challenge.stakes[msg.sender] += _amount;
        challenge.treasury += _amount;
        
        emit ChallengeDepositIncrease(_challengeId, msg.sender, _amount);
    }
    
    /**
     * @dev Submit proof of challenge completion (Zharrior function)
     */
    function submitProof(uint256 _challengeId, string memory _proofUri) 
        external 
        challengeExists(_challengeId)
        whenNotPaused 
    {
        Challenge storage challenge = challenges[_challengeId];
        require(msg.sender == challenge.forCreator, "Only assigned creator can submit proof");
        require(challenge.status == ChallengeStatus.Active, "Challenge not active");
        require(block.timestamp < challenge.expiration, "Challenge expired");
        require(bytes(_proofUri).length > 0, "Proof URI cannot be empty");
        
        challenge.proofUri = _proofUri;
        challenge.proofUpdatedAt = block.timestamp;
        challenge.status = ChallengeStatus.ProofSubmitted;
        
        emit ProofSubmitted(_challengeId, _proofUri);
    }
    
    /**
     * @dev Dispute proof (Stoker function) - weight proportional to stake
     */
    function disputeProof(uint256 _challengeId) 
        external 
        challengeExists(_challengeId)
        whenNotPaused 
    {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.status == ChallengeStatus.ProofSubmitted, "No proof to dispute");
        require(challenge.stakes[msg.sender] > 0, "Only stokers can dispute");
        require(!challenge.disputes[msg.sender], "Already disputed");
        require(
            block.timestamp <= challenge.proofUpdatedAt + challenge.disputePeriod,
            "Dispute period ended"
        );
        
        // Record the dispute
        challenge.disputes[msg.sender] = true;
        uint256 disputeValue = challenge.stakes[msg.sender];
        challenge.totalDisputeValue += disputeValue;
        
        emit ProofDisputed(_challengeId, msg.sender, disputeValue, challenge.totalDisputeValue);
        
        // Check if dispute threshold reached (50% of total treasury)
        if ((challenge.totalDisputeValue * 10000) >= (challenge.treasury * DISPUTE_THRESHOLD)) {
            // Set contest deadline when threshold is reached
            challenge.disputeContestDeadline = block.timestamp + CONTEST_PERIOD;
        }
    }
    
    /**
     * @dev Contest disputes (Challenger function) - available for 2 days after dispute threshold reached
     */
    function contestDisputes(uint256 _challengeId, string memory _reason) 
        external 
        challengeExists(_challengeId)
        whenNotPaused 
    {
        Challenge storage challenge = challenges[_challengeId];
        require(msg.sender == challenge.forCreator, "Only challenge creator can contest");
        require(challenge.status == ChallengeStatus.ProofSubmitted, "Invalid challenge status");
        require(challenge.disputeContestDeadline > 0, "No disputes to contest");
        require(block.timestamp <= challenge.disputeContestDeadline, "Contest period expired");
        require(bytes(_reason).length > 0, "Contest reason cannot be empty");
        
        challenge.contestReason = _reason;
        challenge.status = ChallengeStatus.ValidationByOracle;
        
        emit DisputesContested(_challengeId, msg.sender, _reason);
    }

    // ============ ORACLE FUNCTIONS ============
    
    /**
     * @dev Oracle validates disputed challenge
     */
    function validateChallenge(uint256 _challengeId, bool _approved, string memory _reason) 
        external 
        challengeExists(_challengeId)
        onlyOracle
        whenNotPaused 
    {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.status == ChallengeStatus.ValidationByOracle, "Not awaiting oracle validation");
        
        emit OracleValidation(_challengeId, msg.sender, _approved, _reason);
        
        if (_approved) {
            _completeChallenge(_challengeId);
        } else {
            _failChallenge(_challengeId);
        }
    }
    
    // ============ CLAIM FUNCTIONS ============
    
    /**
     * @dev Claim rewards after dispute period (Zharrior function)
     */
    function claimReward(uint256 _challengeId) 
        external 
        challengeExists(_challengeId) 
        nonReentrant 
        whenNotPaused 
    {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.status == ChallengeStatus.ProofSubmitted, "Invalid status");
        require(challenge.claimedAt == 0, "Already claimed");
        require(
            block.timestamp >= challenge.proofUpdatedAt + challenge.disputePeriod,
            "Dispute period not over"
        );
        
        // Check if dispute threshold was reached
        bool disputeThresholdReached = (challenge.totalDisputeValue * 10000) >= (challenge.treasury * DISPUTE_THRESHOLD);
        
        if (disputeThresholdReached) {
            // Check if challenger contested and contest period expired
            if (challenge.disputeContestDeadline > 0 && 
                block.timestamp > challenge.disputeContestDeadline && 
                challenge.status != ChallengeStatus.ValidationByOracle) {
                // Challenger didn't contest in time, challenge fails
                _failChallenge(_challengeId);
            } else if (challenge.status == ChallengeStatus.ValidationByOracle) {
                // Challenge is contested, awaiting oracle validation
                revert("Challenge awaiting oracle validation");
            } else {
                // Contest period still active
                revert("Contest period still active");
            }
        } else {
            // No significant disputes, complete the challenge
            _completeChallenge(_challengeId);
        }
    }
    
    /**
     * @dev Claim refund for failed or expired challenges (Stoker function)
     */
    function claimRefund(uint256 _challengeId) 
        external 
        challengeExists(_challengeId)
        nonReentrant
        whenNotPaused 
    {
        Challenge storage challenge = challenges[_challengeId];
        console.log("expiration", challenge.expiration);
        console.log("status", uint256(challenge.status));
        console.log("block.timestamp", block.timestamp);
        if(challenge.status == ChallengeStatus.Active) {
            require(block.timestamp >= challenge.expiration, "Challenge not expired");
            challenge.status = ChallengeStatus.Expired;
            emit ChallengeExpired(_challengeId);
        } else if (challenge.status == ChallengeStatus.ProofSubmitted) {
            require(block.timestamp >= challenge.proofUpdatedAt + challenge.disputePeriod, "Dispute period not over");
            challenge.status = ChallengeStatus.Expired;
            emit ChallengeExpired(_challengeId);
        }
        require(
            challenge.status == ChallengeStatus.Failed || 
            challenge.status == ChallengeStatus.Expired, 
            "Challenge not failed or expired"
        );
        require(challenge.stakes[msg.sender] > 0, "No stake to refund");
        
        uint256 refundAmount = challenge.stakes[msg.sender];
        challenge.stakes[msg.sender] = 0;
        
        require(europToken.transfer(msg.sender, refundAmount), "Refund transfer failed");
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @dev Complete challenge and distribute rewards
     */
    function _completeChallenge(uint256 _challengeId) internal {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.treasury > 0, "No funds to distribute");
        
        challenge.status = ChallengeStatus.Completed;
        challenge.claimedAt = block.timestamp;
        
        uint256 totalTreasury = challenge.treasury;
        uint256 zharriorShare = (totalTreasury * ZHARRIOR_SHARE) / 10000;
        uint256 defiShare = (totalTreasury * DEFI_SHARE) / 10000;
        
        // Calculate igniter share with cap
        uint256 maxIgniterShare = (totalTreasury * MAX_IGNITER_SHARE) / 10000;
        uint256 igniterShare = maxIgniterShare > MAX_IGNITER_CAP ? MAX_IGNITER_CAP : maxIgniterShare;
        
        // Remaining goes to Zharrior
        uint256 remainingForZharrior = totalTreasury - igniterShare - defiShare;
        if (remainingForZharrior > zharriorShare) {
            zharriorShare = remainingForZharrior;
        }
        
        // Transfer rewards
        require(europToken.transfer(challenge.forCreator, zharriorShare), "Zharrior transfer failed");
        require(europToken.transfer(challenge.igniter, igniterShare), "Igniter transfer failed");
        require(europToken.transfer(defiTreasury, defiShare), "DeFi transfer failed");

        fireXPToken.mint(challenge.forCreator, zharriorShare);
        fireXPToken.mint(defiTreasury, defiShare);
        for (uint256 i = 0; i < challenge.stokers.length; i++) {
            address stoker = challenge.stokers[i];
            uint256 stake = challenge.stakes[stoker];
            if (stake > 0) {
                fireXPToken.mint(stoker, stake);
            }
        }
        
        // Update creator stats
        creators[challenge.forCreator].totalChallengesCompleted++;
        
        emit ChallengeCompleted(_challengeId, zharriorShare, igniterShare, defiShare);
    }
    
    /**
     * @dev Fail challenge due to disputes - enable refunds
     */
    function _failChallenge(uint256 _challengeId) internal {
        Challenge storage challenge = challenges[_challengeId];
        challenge.status = ChallengeStatus.Failed;
        
        emit ChallengeFailed(_challengeId, challenge.totalDisputeValue, challenge.treasury);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getChallengeStakers(uint256 _challengeId) external view challengeExists(_challengeId) returns (address[] memory, uint256[] memory) {
        Challenge storage challenge = challenges[_challengeId];
        uint256[] memory stakes = new uint256[](challenge.stokers.length);
        
        for (uint256 i = 0; i < challenge.stokers.length; i++) {
            stakes[i] = challenge.stakes[challenge.stokers[i]];
        }
        
        return (challenge.stokers, stakes);
    }
    
    function getChallengeDisputers(uint256 _challengeId) external view challengeExists(_challengeId) returns (address[] memory, uint256[] memory) {
        Challenge storage challenge = challenges[_challengeId];
        
        // Count disputers first
        uint256 disputerCount = 0;
        for (uint256 i = 0; i < challenge.stokers.length; i++) {
            if (challenge.disputes[challenge.stokers[i]]) {
                disputerCount++;
            }
        }
        
        // Create arrays
        address[] memory disputers = new address[](disputerCount);
        uint256[] memory disputeValues = new uint256[](disputerCount);
        
        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 0; i < challenge.stokers.length; i++) {
            address stoker = challenge.stokers[i];
            if (challenge.disputes[stoker]) {
                disputers[index] = stoker;
                disputeValues[index] = challenge.stakes[stoker];
                index++;
            }
        }
        
        return (disputers, disputeValues);
    }
    
    function getDisputeStatus(uint256 _challengeId) external view challengeExists(_challengeId) returns (
        uint256 totalDisputeValue,
        uint256 totalTreasury,
        uint256 disputePercentage,
        bool thresholdReached,
        uint256 timeLeft,
        uint256 contestDeadline
    ) {
        Challenge storage challenge = challenges[_challengeId];
        
        totalDisputeValue = challenge.totalDisputeValue;
        totalTreasury = challenge.treasury;
        disputePercentage = totalTreasury > 0 ? (totalDisputeValue * 10000) / totalTreasury : 0;
        thresholdReached = disputePercentage >= DISPUTE_THRESHOLD;
        contestDeadline = challenge.disputeContestDeadline;
        
        if (challenge.status == ChallengeStatus.ProofSubmitted && challenge.proofUpdatedAt > 0) {
            uint256 disputeEndTime = challenge.proofUpdatedAt + challenge.disputePeriod;
            timeLeft = block.timestamp < disputeEndTime ? disputeEndTime - block.timestamp : 0;
        }
        
        return (totalDisputeValue, totalTreasury, disputePercentage, thresholdReached, timeLeft, contestDeadline);
    }
    
    function getContestInfo(uint256 _challengeId) external view challengeExists(_challengeId) returns (
        uint256 contestDeadline,
        bool canContest
    ) {
        Challenge storage challenge = challenges[_challengeId];
        
        contestDeadline = challenge.disputeContestDeadline;
        canContest = (
            challenge.status == ChallengeStatus.ProofSubmitted &&
            challenge.disputeContestDeadline > 0 &&
            block.timestamp <= challenge.disputeContestDeadline
        );
        
        return (contestDeadline, canContest);
    }
    
    function getUserChallenges(address _user) external view returns (uint256[] memory) {
        return userChallenges[_user];
    }
    
    function canUserDispute(uint256 _challengeId, address _user) external view challengeExists(_challengeId) returns (bool) {
        Challenge storage challenge = challenges[_challengeId];
        return (
            challenge.status == ChallengeStatus.ProofSubmitted &&
            challenge.stakes[_user] > 0 &&
            !challenge.disputes[_user] &&
            block.timestamp <= challenge.proofUpdatedAt + challenge.disputePeriod
        );
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function setDefiTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Invalid address");
        defiTreasury = _newTreasury;
    }
    
    function setOracleAddress(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid address");
        address oldOracle = tempOracleAddress;
        tempOracleAddress = _newOracle;
        emit OracleAddressUpdated(oldOracle, _newOracle);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // Emergency function to recover stuck tokens
    function emergencyWithdraw(address _token, address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        IERC20(_token).transfer(_to, _amount);
    }
}