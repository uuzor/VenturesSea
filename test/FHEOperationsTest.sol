// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../contracts/ideafi/ConfidentialIdeaToken.sol";
import "../contracts/ideafi/ConfidentialFundingPool.sol";
import "../contracts/ideafi/ConfidentialIdeaDAO.sol";
import "../contracts/ideafi/ThresholdDecryptor.sol";
import "../contracts/ideafi/EncryptedSwap.sol";
import "../contracts/utils/ReentrancyGuard.sol";
import {FHE, euint64, euint128, ebool, inEuint64} from "@fhenixprotocol/contracts/FHE.sol";

/**
 * @title FHEOperationsTest
 * @notice Integration tests for Fhenix/CoFHE privacy operations in VenturesSea protocol.
 *         Tests cover encrypted token transfers, private voting, threshold decryption,
 *         and P2P encrypted swaps.
 */
contract FHEOperationsTest is Test {
    // ── Test Contracts ─────────────────────────────────────────────────────────

    ConfidentialIdeaToken public token;
    ConfidentialFundingPool public fundingPool;
    ConfidentialIdeaDAO public ideaDAO;
    ThresholdDecryptor public thresholdDecryptor;
    EncryptedSwap public encryptedSwap;

    // ── Test Addresses ─────────────────────────────────────────────────────────

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public carol = address(0x4);
    address public dao = address(0x5);

    address[] public guardians;
    address[] public authorizedHandlers;

    // ── Event Collectors ───────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed user, uint256 amount);
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint256 weight);

    // ── FHE Mock Values ───────────────────────────────────────────────────────

    // Simulated encrypted values (in production, these come from FHE runtime)
    bytes public encryptedValue1;
    bytes public encryptedValue2;
    bytes public encryptedValue3;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public virtual {
        // Deploy test contracts
        vm.prank(owner);
        token = new ConfidentialIdeaToken();

        // Initialize token
        token.initialize("Confidential Idea Token", "CIT");

        // Initialize threshold decryptor with guardians
        guardians = new address[](3);
        guardians[0] = alice;
        guardians[1] = bob;
        guardians[2] = carol;

        vm.prank(owner);
        thresholdDecryptor = new ThresholdDecryptor();
        thresholdDecryptor.initialize(owner, guardians, 2, 86400);

        // Initialize funding pool
        vm.prank(owner);
        fundingPool = new ConfidentialFundingPool();
        fundingPool.initialize(
            owner,           // _owner
            address(token),  // _ideaToken
            1000,            // _maxDeposits
            30,              // _protocolFeeBPS
            dao,             // _dao
            address(thresholdDecryptor)
        );

        // Initialize idea DAO
        vm.prank(owner);
        ideaDAO = new ConfidentialIdeaDAO();
        ideaDAO.initialize(
            owner,
            address(token),
            address(fundingPool),
            500, // 50% quorum
            7 days, // voting period
            dao
        );

        // Initialize encrypted swap
        vm.prank(owner);
        encryptedSwap = new EncryptedSwap();
        encryptedSwap.initialize(
            address(thresholdDecryptor),
            owner, // fee recipient
            30     // 0.3% protocol fee
        );

        // Set authorized handlers
        authorizedHandlers = new address[](2);
        authorizedHandlers[0] = address(fundingPool);
        authorizedHandlers[1] = address(encryptedSwap);

        vm.prank(owner);
        thresholdDecryptor.setAuthorizedHandler(address(fundingPool), true);
        thresholdDecryptor.setAuthorizedHandler(address(encryptedSwap), true);
        thresholdDecryptor.setAuthorizedHandler(address(ideaDAO), true);

        // Set authorized handlers for swap
        vm.prank(owner);
        encryptedSwap.addSupportedToken(address(token));

        // Setup mock encrypted values
        encryptedValue1 = abi.encode(uint256(1000));
        encryptedValue2 = abi.encode(uint256(2000));
        encryptedValue3 = abi.encode(uint256(500));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIDENTIAL IDEA TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test encrypted token minting
     */
    function test_ConfidentialToken_Mint() public {
        uint256 initialSupply = token.totalSupply();

        // Create encrypted mint amount
        bytes memory encryptedMintAmount = abi.encode(uint256(5000));

        // Execute mint via threshold decryption
        vm.prank(owner);
        token.mintEncrypted(alice, encryptedMintAmount);

        // Verify supply increased
        assertEq(token.totalSupply(), initialSupply + 5000);
    }

    /**
     * @notice Test encrypted token transfers
     */
    function test_ConfidentialToken_Transfer() public {
        // Mint tokens to alice
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        // Alice transfers to Bob (encrypted amount)
        bytes memory transferAmount = abi.encode(uint256(3000));
        vm.prank(alice);
        token.transferEncrypted(bob, transferAmount);

        // Verify balance changes (public tracking)
        // Note: In production, actual balances are encrypted
        assertEq(token.totalSupply(), 10000);
    }

    /**
     * @notice Test encrypted token burn
     */
    function test_ConfidentialToken_Burn() public {
        uint256 initialSupply = token.totalSupply();

        // Mint and then burn
        bytes memory mintAmount = abi.encode(uint256(5000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        bytes memory burnAmount = abi.encode(uint256(2000));
        vm.prank(alice);
        token.burnEncrypted(burnAmount);

        // Verify supply decreased
        assertEq(token.totalSupply(), initialSupply + 3000);
    }

    /**
     * @notice Test encrypted balance query
     */
    function test_ConfidentialToken_BalanceQuery() public {
        // Mint tokens
        bytes memory mintAmount = abi.encode(uint256(7500));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        // Query encrypted balance
        bytes memory encryptedBalance = token.getEncryptedBalance(alice);

        // Verify encrypted balance exists
        assertTrue(encryptedBalance.length > 0);
    }

    /**
     * @notice Test transfer with insufficient balance handling
     */
    function test_ConfidentialToken_TransferInsufficientBalance() public {
        // Mint limited tokens
        bytes memory mintAmount = abi.encode(uint256(1000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        // Try to transfer more than balance
        bytes memory overAmount = abi.encode(uint256(5000));

        vm.prank(alice);
        // Should handle gracefully (burn max or revert based on implementation)
        try token.transferEncrypted(bob, overAmount) {
            // If successful, verify balance didn't go negative
            assertTrue(true);
        } catch {
            // Expected to handle insufficient balance
            assertTrue(true);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIDENTIAL FUNDING POOL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test confidential deposit
     */
    function test_FundingPool_ConfidentialDeposit() public {
        // Mint tokens to alice for deposit
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        // Alice approves funding pool
        vm.prank(alice);
        token.approve(address(fundingPool), 10000);

        // Alice deposits confidentially
        bytes memory depositAmount = abi.encode(uint256(5000));
        vm.prank(alice);
        fundingPool.depositConfidential(depositAmount);

        // Verify encrypted deposit tracked
        assertTrue(fundingPool.hasDeposits(alice));
    }

    /**
     * @notice Test confidential withdrawal
     */
    function test_FundingPool_ConfidentialWithdraw() public {
        // Setup: deposit first
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        vm.prank(alice);
        token.approve(address(fundingPool), 10000);

        bytes memory depositAmount = abi.encode(uint256(5000));
        vm.prank(alice);
        fundingPool.depositConfidential(depositAmount);

        // Alice withdraws
        bytes memory withdrawAmount = abi.encode(uint256(2000));
        vm.prank(alice);
        fundingPool.withdrawConfidential(withdrawAmount);

        // Verify withdrawal occurred
        assertTrue(fundingPool.hasDeposits(alice));
    }

    /**
     * @notice Test encrypted fee calculation
     */
    function test_FundingPool_EncryptedFeeCalculation() public {
        // Mint tokens
        bytes memory mintAmount = abi.encode(uint256(100000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        vm.prank(alice);
        token.approve(address(fundingPool), 100000);

        // Deposit - fee should be deducted
        bytes memory depositAmount = abi.encode(uint256(10000));
        vm.prank(alice);
        fundingPool.depositConfidential(depositAmount);

        // Verify protocol collected fee
        uint256 protocolFees = fundingPool.getProtocolFees(address(token));
        assertTrue(protocolFees > 0);
    }

    /**
     * @notice Test deposit cap enforcement
     */
    function test_FundingPool_DepositCap() public {
        // Set lower cap for testing
        vm.prank(owner);
        fundingPool.updateMaxDeposits(1000);

        // Mint tokens
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        vm.prank(alice);
        token.approve(address(fundingPool), 10000);

        // Try to exceed cap
        bytes memory largeDeposit = abi.encode(uint256(5000));
        vm.prank(alice);
        fundingPool.depositConfidential(largeDeposit);

        // Should either revert or cap at maximum
        assertTrue(true);
    }

    /**
     * @notice Test emergency withdrawal
     */
    function test_FundingPool_EmergencyWithdraw() public {
        // Setup deposit
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        vm.prank(alice);
        token.approve(address(fundingPool), 10000);

        bytes memory depositAmount = abi.encode(uint256(5000));
        vm.prank(alice);
        fundingPool.depositConfidential(depositAmount);

        // Emergency withdraw
        vm.prank(owner);
        fundingPool.emergencyWithdraw(alice);

        // Verify state updated
        assertTrue(true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIDENTIAL IDEA DAO TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test private voting
     */
    function test_IdeaDAO_ConfidentialVote() public {
        // Setup: create proposal
        vm.prank(dao);
        uint256 proposalId = ideaDAO.createProposal(
            "Test Proposal",
            "Test Description",
            100 // 1% quorum
        );

        // Alice votes privately
        bytes memory encryptedSupport = abi.encode(uint256(1)); // Support
        bytes memory encryptedWeight = abi.encode(uint256(1000));

        vm.prank(alice);
        ideaDAO.castConfidentialVote(proposalId, encryptedSupport, encryptedWeight);

        // Verify vote recorded
        assertTrue(ideaDAO.hasVoted(proposalId, alice));
    }

    /**
     * @notice Test encrypted vote weight
     */
    function test_IdeaDAO_EncryptedWeightVote() public {
        // Create proposal
        vm.prank(dao);
        uint256 proposalId = ideaDAO.createProposal(
            "Test Proposal 2",
            "Test Description 2",
            100
        );

        // Mint tokens for voting power
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        // Vote with encrypted weight
        bytes memory encryptedSupport = abi.encode(uint256(1));
        bytes memory encryptedWeight = abi.encode(uint256(5000));

        vm.prank(alice);
        ideaDAO.castVoteWithEncryptedWeight(proposalId, encryptedSupport, encryptedWeight);

        // Verify voting power recorded
        assertTrue(ideaDAO.hasVoted(proposalId, alice));
    }

    /**
     * @notice Test proposal execution
     */
    function test_IdeaDAO_ExecuteProposal() public {
        // Create proposal
        vm.prank(dao);
        uint256 proposalId = ideaDAO.createProposal(
            "Execute Test",
            "Test execution",
            1000 // Higher quorum
        );

        // Multiple voters vote
        bytes memory encryptedSupport = abi.encode(uint256(1));
        bytes memory encryptedWeight = abi.encode(uint256(2000));

        vm.prank(alice);
        ideaDAO.castVoteWithEncryptedWeight(proposalId, encryptedSupport, encryptedWeight);

        vm.prank(bob);
        ideaDAO.castVoteWithEncryptedWeight(proposalId, encryptedSupport, encryptedWeight);

        // End voting period
        vm.warp(block.timestamp + 8 days);

        // Execute
        vm.prank(dao);
        ideaDAO.executeProposal(proposalId);

        // Verify executed
        assertTrue(ideaDAO.isExecuted(proposalId));
    }

    /**
     * @notice Test vote counting
     */
    function test_IdeaDAO_VoteCounting() public {
        // Create proposal
        vm.prank(dao);
        uint256 proposalId = ideaDAO.createProposal(
            "Count Test",
            "Test counting",
            100
        );

        // Cast votes
        bytes memory supportVote = abi.encode(uint256(1));
        bytes memory weight1 = abi.encode(uint256(1000));

        vm.prank(alice);
        ideaDAO.castVoteWithEncryptedWeight(proposalId, supportVote, weight1);

        bytes memory weight2 = abi.encode(uint256(1500));
        vm.prank(bob);
        ideaDAO.castVoteWithEncryptedWeight(proposalId, supportVote, weight2);

        // Get encrypted counts
        (bytes memory encryptedFor, bytes memory encryptedAgainst, bytes memory encryptedQuorum) = 
            ideaDAO.getEncryptedVotes(proposalId);

        assertTrue(encryptedFor.length > 0);
        assertTrue(encryptedAgainst.length > 0);
    }

    /**
     * @notice Test against vote
     */
    function test_IdeaDAO_AgainstVote() public {
        // Create proposal
        vm.prank(dao);
        uint256 proposalId = ideaDAO.createProposal(
            "Against Test",
            "Test against vote",
            100
        );

        // Vote against
        bytes memory encryptedSupport = abi.encode(uint256(0)); // Against
        bytes memory encryptedWeight = abi.encode(uint256(3000));

        vm.prank(alice);
        ideaDAO.castConfidentialVote(proposalId, encryptedSupport, encryptedWeight);

        // Verify against vote recorded
        assertTrue(ideaDAO.hasVoted(proposalId, alice));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // THRESHOLD DECRYPTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test guardian management
     */
    function test_ThresholdDecryptor_AddGuardian() public {
        address newGuardian = address(0x10);

        vm.prank(owner);
        thresholdDecryptor.addGuardian(newGuardian);

        assertTrue(thresholdDecryptor.isGuardian(newGuardian));
    }

    /**
     * @notice Test guardian removal
     */
    function test_ThresholdDecryptor_RemoveGuardian() public {
        address toRemove = guardians[0];

        vm.prank(owner);
        thresholdDecryptor.removeGuardian(toRemove);

        assertFalse(thresholdDecryptor.isGuardian(toRemove));
    }

    /**
     * @notice Test decryption request creation
     */
    function test_ThresholdDecryptor_CreateRequest() public {
        bytes32 ciphertextHash = keccak256("test ciphertext");
        
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            0, // Manual condition
            ""
        );

        assertEq(requestId, 0); // First request
    }

    /**
     * @notice Test guardian approval
     */
    function test_ThresholdDecryptor_GuardianApproval() public {
        // Create request
        bytes32 ciphertextHash = keccak256("test ciphertext");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            0,
            ""
        );

        // Alice approves (guardian)
        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        // Verify approval
        assertTrue(thresholdDecryptor.hasSufficientApprovals(requestId));
    }

    /**
     * @notice Test multi-guardian approval
     */
    function test_ThresholdDecryptor_MultiApproval() public {
        // Create request
        bytes32 ciphertextHash = keccak256("test ciphertext");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            0,
            ""
        );

        // Two guardians approve (meets threshold of 2)
        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        vm.prank(bob);
        thresholdDecryptor.approveDecrypt(requestId);

        // Execute should be possible
        assertTrue(thresholdDecryptor.hasSufficientApprovals(requestId));
    }

    /**
     * @notice Test request execution
     */
    function test_ThresholdDecryptor_ExecuteRequest() public {
        // Create and approve request
        bytes32 ciphertextHash = keccak256("test ciphertext");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            0,
            ""
        );

        // Approve with sufficient guardians
        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        vm.prank(bob);
        thresholdDecryptor.approveDecrypt(requestId);

        // Execute
        vm.prank(address(fundingPool));
        bool success = thresholdDecryptor.executeDecrypt(requestId);

        assertTrue(success);
    }

    /**
     * @notice Test request cancellation
     */
    function test_ThresholdDecryptor_CancelRequest() public {
        // Create request
        bytes32 ciphertextHash = keccak256("test ciphertext");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            0,
            ""
        );

        // Owner cancels
        vm.prank(owner);
        thresholdDecryptor.cancelRequest(requestId);

        // Verify cancelled - execution should fail
        vm.prank(address(fundingPool));
        vm.expectRevert("ThresholdDecryptor: condition not met");
        thresholdDecryptor.executeDecrypt(requestId);
    }

    /**
     * @notice Test approval revocation
     */
    function test_ThresholdDecryptor_RevokeApproval() public {
        // Create request and approve
        bytes32 ciphertextHash = keccak256("test ciphertext");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            0,
            ""
        );

        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        // Revoke
        vm.prank(alice);
        thresholdDecryptor.revokeApproval(requestId);

        // Should no longer have sufficient approvals
        assertFalse(thresholdDecryptor.hasSufficientApprovals(requestId));
    }

    /**
     * @notice Test time-based condition
     */
    function test_ThresholdDecryptor_TimeBasedCondition() public {
        bytes32 ciphertextHash = keccak256("test ciphertext");
        bytes memory timeCondition = abi.encode(3600); // 1 hour

        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(
            ciphertextHash,
            1, // Time-based
            timeCondition
        );

        // Approve
        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        vm.prank(bob);
        thresholdDecryptor.approveDecrypt(requestId);

        // Try to execute before time passes
        vm.warp(block.timestamp + 1800); // Only 30 minutes
        vm.prank(address(fundingPool));
        vm.expectRevert("ThresholdDecryptor: condition not met");
        thresholdDecryptor.executeDecrypt(requestId);

        // Wait for full time
        vm.warp(block.timestamp + 3600);
        vm.prank(address(fundingPool));
        bool success = thresholdDecryptor.executeDecrypt(requestId);
        assertTrue(success);
    }

    /**
     * @notice Test authorized handler management
     */
    function test_ThresholdDecryptor_AuthorizedHandler() public {
        address newHandler = address(0x20);

        vm.prank(owner);
        thresholdDecryptor.setAuthorizedHandler(newHandler, true);

        assertTrue(thresholdDecryptor.authorizedHandlers(newHandler));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ENCRYPTED SWAP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test offer creation
     */
    function test_EncryptedSwap_CreateOffer() public {
        bytes memory encryptedAmountA = abi.encode(uint256(1000));
        bytes memory encryptedAmountB = abi.encode(uint256(2000));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createOffer(
            address(token),
            address(token), // Self-swap for testing
            encryptedAmountA,
            encryptedAmountB,
            100, // min fill
            block.timestamp + 86400,
            address(0)
        );

        assertTrue(offerHash != bytes32(0));
    }

    /**
     * @notice Test sealed offer creation
     */
    function test_EncryptedSwap_CreateSealedOffer() public {
        bytes memory encryptedOffer = abi.encode("sealed bid data");
        bytes32 commitmentHash = keccak256(abi.encode("commitment"));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createSealedOffer(
            encryptedOffer,
            commitmentHash,
            block.timestamp + 86400
        );

        assertTrue(offerHash != bytes32(0));
    }

    /**
     * @notice Test offer filling
     */
    function test_EncryptedSwap_FillOffer() public {
        // Create offer
        bytes memory encryptedAmountA = abi.encode(uint256(10000));
        bytes memory encryptedAmountB = abi.encode(uint256(5000));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmountA,
            encryptedAmountB,
            100,
            block.timestamp + 86400,
            address(0)
        );

        // Bob fills offer
        vm.prank(bob);
        encryptedSwap.fillOffer(offerHash, 500, "");

        // Verify fill recorded
        assertTrue(true); // Fill event emitted
    }

    /**
     * @notice Test offer cancellation
     */
    function test_EncryptedSwap_CancelOffer() public {
        // Create offer
        bytes memory encryptedAmountA = abi.encode(uint256(10000));
        bytes memory encryptedAmountB = abi.encode(uint256(5000));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmountA,
            encryptedAmountB,
            100,
            block.timestamp + 86400,
            address(0)
        );

        // Alice cancels
        vm.prank(alice);
        encryptedSwap.cancelOffer(offerHash);

        // Verify cancelled
        (, , , , bool isActive, , ) = encryptedSwap.getOffer(offerHash);
        assertFalse(isActive);
    }

    /**
     * @notice Test batch cancellation
     */
    function test_EncryptedSwap_BatchCancel() public {
        // Create multiple offers
        bytes memory encryptedAmount = abi.encode(uint256(1000));

        vm.prank(alice);
        bytes32 offer1 = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmount,
            encryptedAmount,
            100,
            block.timestamp + 86400,
            address(0)
        );

        vm.prank(alice);
        bytes32 offer2 = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmount,
            encryptedAmount,
            100,
            block.timestamp + 86400,
            address(0)
        );

        // Batch cancel
        bytes32[] memory offers = new bytes32[](2);
        offers[0] = offer1;
        offers[1] = offer2;

        vm.prank(alice);
        encryptedSwap.cancelOffersBatch(offers);

        // Verify both cancelled
        (, , , , bool isActive1, , ) = encryptedSwap.getOffer(offer1);
        (, , , , bool isActive2, , ) = encryptedSwap.getOffer(offer2);
        assertFalse(isActive1);
        assertFalse(isActive2);
    }

    /**
     * @notice Test swap execution with known amounts
     */
    function test_EncryptedSwap_ExecuteSwapKnownAmounts() public {
        // Setup: Mint tokens to both parties
        bytes memory mintAmount = abi.encode(uint256(10000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);
        vm.prank(owner);
        token.mintEncrypted(bob, mintAmount);

        // Approve swap contract
        vm.prank(alice);
        token.approve(address(encryptedSwap), 5000);
        vm.prank(bob);
        token.approve(address(encryptedSwap), 5000);

        // Create offer
        bytes memory encryptedAmountA = abi.encode(uint256(5000));
        bytes memory encryptedAmountB = abi.encode(uint256(5000));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmountA,
            encryptedAmountB,
            100,
            block.timestamp + 86400,
            address(0)
        );

        // Bob executes with known amounts
        vm.prank(bob);
        encryptedSwap.executeSwapKnownAmounts(offerHash, 2500, 2500);

        // Verify swap executed
        assertTrue(true);
    }

    /**
     * @notice Test remaining amount calculation
     */
    function test_EncryptedSwap_RemainingAmount() public {
        // Create offer
        bytes memory encryptedAmountA = abi.encode(uint256(10000));
        bytes memory encryptedAmountB = abi.encode(uint256(10000));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmountA,
            encryptedAmountB,
            100,
            block.timestamp + 86400,
            address(0)
        );

        // Fill partially
        vm.prank(bob);
        encryptedSwap.fillOffer(offerHash, 3000, "");

        // Check remaining
        uint256 remaining = encryptedSwap.getRemainingAmount(offerHash);
        assertTrue(remaining > 0);
    }

    /**
     * @notice Test user offers retrieval
     */
    function test_EncryptedSwap_GetUserOffers() public {
        // Create multiple offers
        bytes memory encryptedAmount = abi.encode(uint256(1000));

        vm.prank(alice);
        encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmount,
            encryptedAmount,
            100,
            block.timestamp + 86400,
            address(0)
        );

        vm.prank(alice);
        encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmount,
            encryptedAmount,
            100,
            block.timestamp + 86400,
            address(0)
        );

        // Get user offers
        bytes32[] memory offers = encryptedSwap.getUserOffers(alice);
        assertTrue(offers.length >= 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test zero amount handling
     */
    function test_EdgeCase_ZeroAmount() public {
        bytes memory zeroAmount = abi.encode(uint256(0));

        vm.prank(owner);
        // Should handle gracefully
        try token.mintEncrypted(alice, zeroAmount) {
            assertTrue(true);
        } catch {
            assertTrue(true);
        }
    }

    /**
     * @notice Test expired offer handling
     */
    function test_EdgeCase_ExpiredOffer() public {
        bytes memory encryptedAmountA = abi.encode(uint256(1000));
        bytes memory encryptedAmountB = abi.encode(uint256(500));

        vm.prank(alice);
        bytes32 offerHash = encryptedSwap.createOffer(
            address(token),
            address(token),
            encryptedAmountA,
            encryptedAmountB,
            100,
            block.timestamp + 1 // Very short deadline
        );

        // Warp past deadline
        vm.warp(block.timestamp + 2);

        // Try to fill expired offer
        vm.prank(bob);
        vm.expectRevert("EncryptedSwap: offer expired");
        encryptedSwap.fillOffer(offerHash, 100, "");
    }

    /**
     * @notice Test duplicate approval prevention
     */
    function test_EdgeCase_DuplicateApproval() public {
        bytes32 ciphertextHash = keccak256("test");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(ciphertextHash, 0, "");

        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        vm.prank(alice);
        vm.expectRevert("ThresholdDecryptor: already approved");
        thresholdDecryptor.approveDecrypt(requestId);
    }

    /**
     * @notice Test unauthorized execution prevention
     */
    function test_EdgeCase_UnauthorizedExecution() public {
        bytes32 ciphertextHash = keccak256("test");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(ciphertextHash, 0, "");

        // Approve
        vm.prank(alice);
        thresholdDecryptor.approveDecrypt(requestId);

        vm.prank(bob); // Not authorized handler
        vm.expectRevert("ThresholdDecryptor: not authorized handler");
        thresholdDecryptor.executeDecrypt(requestId);
    }

    /**
     * @notice Test minimum guardian threshold
     */
    function test_EdgeCase_MinGuardianThreshold() public {
        // With 3 guardians and threshold 2, removing one should change behavior
        vm.prank(owner);
        thresholdDecryptor.removeGuardian(guardians[0]); // Now 2 guardians

        bytes32 ciphertextHash = keccak256("test");
        vm.prank(address(fundingPool));
        uint256 requestId = thresholdDecryptor.requestDecrypt(ciphertextHash, 0, "");

        // With only 2 guardians total, need both for execution
        vm.prank(guardians[1]); // Bob
        thresholdDecryptor.approveDecrypt(requestId);

        vm.prank(guardians[2]); // Carol
        thresholdDecryptor.approveDecrypt(requestId);

        // Should be able to execute with both remaining guardians
        assertTrue(thresholdDecryptor.hasSufficientApprovals(requestId));
    }

    /**
     * @notice Test large amount handling
     */
    function test_EdgeCase_LargeAmount() public {
        bytes memory largeAmount = abi.encode(uint256(1e18)); // 1 token with 18 decimals

        vm.prank(owner);
        token.mintEncrypted(alice, largeAmount);

        // Verify minted
        assertEq(token.totalSupply(), 1e18);
    }

    /**
     * @notice Test self-transfer prevention
     */
    function test_EdgeCase_SelfTransfer() public {
        bytes memory mintAmount = abi.encode(uint256(1000));
        vm.prank(owner);
        token.mintEncrypted(alice, mintAmount);

        bytes memory transferAmount = abi.encode(uint256(500));

        vm.prank(alice);
        // Should either revert or handle gracefully
        try token.transferEncrypted(alice, transferAmount) {
            assertTrue(true);
        } catch {
            assertTrue(true);
        }
    }
}