// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Renewable Energy Trading Grid
 * @dev A decentralized platform for peer-to-peer renewable energy trading
 * @author Renewable Energy Trading Grid Team
 */
contract RenewableEnergyTradingGrid {
    
    // State variables
    address public owner;
    uint256 public totalEnergyTraded;
    uint256 public totalTransactions;
    uint256 private constant ENERGY_PRECISION = 1e18; // 18 decimal precision for energy units (kWh)
    
    // Structs
    struct EnergyListing {
        uint256 id;
        address producer;
        uint256 energyAmount; // in kWh (with 18 decimal precision)
        uint256 pricePerKWh; // in wei per kWh
        uint256 timestamp;
        bool isActive;
        bool isCompleted;
    }
    
    struct EnergyProducer {
        address producerAddress;
        uint256 totalEnergyProduced;
        uint256 totalEnergyTraded;
        uint256 reputationScore;
        bool isVerified;
        uint256 joinedTimestamp;
    }
    
    struct EnergyTransaction {
        uint256 listingId;
        address buyer;
        address producer;
        uint256 energyAmount;
        uint256 totalPrice;
        uint256 timestamp;
        bool isCompleted;
    }
    
    // Mappings
    mapping(uint256 => EnergyListing) public energyListings;
    mapping(address => EnergyProducer) public energyProducers;
    mapping(uint256 => EnergyTransaction) public energyTransactions;
    mapping(address => uint256[]) public producerListings;
    mapping(address => uint256[]) public buyerTransactions;
    
    // State tracking
    uint256 public nextListingId = 1;
    uint256 public nextTransactionId = 1;
    
    // Events
    event EnergyListed(uint256 indexed listingId, address indexed producer, uint256 energyAmount, uint256 pricePerKWh);
    event EnergyPurchased(uint256 indexed transactionId, uint256 indexed listingId, address indexed buyer, address producer, uint256 energyAmount, uint256 totalPrice);
    event ProducerRegistered(address indexed producer, uint256 timestamp);
    event EnergyDelivered(uint256 indexed transactionId, uint256 energyAmount);
    event ReputationUpdated(address indexed producer, uint256 newScore);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can call this function");
        _;
    }
    
    modifier onlyVerifiedProducer() {
        require(energyProducers[msg.sender].isVerified, "Only verified producers can list energy");
        _;
    }
    
    modifier validListing(uint256 _listingId) {
        require(_listingId > 0 && _listingId < nextListingId, "Invalid listing ID");
        require(energyListings[_listingId].isActive, "Listing is not active");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        totalEnergyTraded = 0;
        totalTransactions = 0;
    }
    
    /**
     * @dev Core Function 1: Register as an energy producer and list energy for sale
     * @param _energyAmount Amount of energy to list (in kWh with 18 decimal precision)
     * @param _pricePerKWh Price per kWh in wei
     */
    function listEnergyForSale(uint256 _energyAmount, uint256 _pricePerKWh) external {
        require(_energyAmount > 0, "Energy amount must be greater than zero");
        require(_pricePerKWh > 0, "Price per kWh must be greater than zero");
        
        // Register producer if not already registered
        if (energyProducers[msg.sender].producerAddress == address(0)) {
            energyProducers[msg.sender] = EnergyProducer({
                producerAddress: msg.sender,
                totalEnergyProduced: 0,
                totalEnergyTraded: 0,
                reputationScore: 100, // Starting reputation score
                isVerified: true, // Auto-verify for demo purposes
                joinedTimestamp: block.timestamp
            });
            emit ProducerRegistered(msg.sender, block.timestamp);
        }
        
        // Create energy listing
        energyListings[nextListingId] = EnergyListing({
            id: nextListingId,
            producer: msg.sender,
            energyAmount: _energyAmount,
            pricePerKWh: _pricePerKWh,
            timestamp: block.timestamp,
            isActive: true,
            isCompleted: false
        });
        
        // Update producer's listings
        producerListings[msg.sender].push(nextListingId);
        
        // Update producer's total energy produced
        energyProducers[msg.sender].totalEnergyProduced += _energyAmount;
        
        emit EnergyListed(nextListingId, msg.sender, _energyAmount, _pricePerKWh);
        nextListingId++;
    }
    
    /**
     * @dev Core Function 2: Purchase energy from a listed producer
     * @param _listingId ID of the energy listing to purchase from
     * @param _energyAmount Amount of energy to purchase (in kWh with 18 decimal precision)
     */
    function purchaseEnergy(uint256 _listingId, uint256 _energyAmount) external payable validListing(_listingId) {
        EnergyListing storage listing = energyListings[_listingId];
        require(_energyAmount > 0 && _energyAmount <= listing.energyAmount, "Invalid energy amount");
        require(msg.sender != listing.producer, "Producers cannot buy their own energy");
        
        // Calculate total price
        uint256 totalPrice = (_energyAmount * listing.pricePerKWh) / ENERGY_PRECISION;
        require(msg.value >= totalPrice, "Insufficient payment");
        
        // Create transaction record
        energyTransactions[nextTransactionId] = EnergyTransaction({
            listingId: _listingId,
            buyer: msg.sender,
            producer: listing.producer,
            energyAmount: _energyAmount,
            totalPrice: totalPrice,
            timestamp: block.timestamp,
            isCompleted: false
        });
        
        // Update buyer's transaction history
        buyerTransactions[msg.sender].push(nextTransactionId);
        
        // Update listing
        listing.energyAmount -= _energyAmount;
        if (listing.energyAmount == 0) {
            listing.isActive = false;
            listing.isCompleted = true;
        }
        
        // Update producer stats
        energyProducers[listing.producer].totalEnergyTraded += _energyAmount;
        
        // Update global stats
        totalEnergyTraded += _energyAmount;
        totalTransactions++;
        
        // Transfer payment to producer
        payable(listing.producer).transfer(totalPrice);
        
        // Refund excess payment to buyer
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
        
        emit EnergyPurchased(nextTransactionId, _listingId, msg.sender, listing.producer, _energyAmount, totalPrice);
        nextTransactionId++;
    }
    
    /**
     * @dev Core Function 3: Verify energy delivery and update reputation (Oracle integration point)
     * @param _transactionId ID of the transaction to verify
     * @param _actualEnergyDelivered Actual energy delivered as verified by smart meters
     */
    function verifyEnergyDelivery(uint256 _transactionId, uint256 _actualEnergyDelivered) external onlyOwner {
        require(_transactionId > 0 && _transactionId < nextTransactionId, "Invalid transaction ID");
        
        EnergyTransaction storage transaction = energyTransactions[_transactionId];
        require(!transaction.isCompleted, "Transaction already completed");
        
        // Mark transaction as completed
        transaction.isCompleted = true;
        
        // Update producer reputation based on delivery accuracy
        address producer = transaction.producer;
        EnergyProducer storage producerData = energyProducers[producer];
        
        // Calculate delivery accuracy (100% = perfect delivery)
        uint256 deliveryAccuracy = (_actualEnergyDelivered * 100) / transaction.energyAmount;
        
        // Update reputation score based on delivery accuracy
        if (deliveryAccuracy >= 95) {
            // Excellent delivery - increase reputation
            producerData.reputationScore += 5;
        } else if (deliveryAccuracy >= 85) {
            // Good delivery - slight increase
            producerData.reputationScore += 2;
        } else if (deliveryAccuracy >= 75) {
            // Average delivery - no change
            // No reputation change
        } else {
            // Poor delivery - decrease reputation
            if (producerData.reputationScore >= 10) {
                producerData.reputationScore -= 10;
            }
        }
        
        // Cap reputation score at 1000
        if (producerData.reputationScore > 1000) {
            producerData.reputationScore = 1000;
        }
        
        emit EnergyDelivered(_transactionId, _actualEnergyDelivered);
        emit ReputationUpdated(producer, producerData.reputationScore);
    }
    
    // View functions
    function getEnergyListing(uint256 _listingId) external view returns (EnergyListing memory) {
        return energyListings[_listingId];
    }
    
    function getEnergyProducer(address _producer) external view returns (EnergyProducer memory) {
        return energyProducers[_producer];
    }
    
    function getEnergyTransaction(uint256 _transactionId) external view returns (EnergyTransaction memory) {
        return energyTransactions[_transactionId];
    }
    
    function getProducerListings(address _producer) external view returns (uint256[] memory) {
        return producerListings[_producer];
    }
    
    function getBuyerTransactions(address _buyer) external view returns (uint256[] memory) {
        return buyerTransactions[_buyer];
    }
    
    function getActiveListingsCount() external view returns (uint256) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i < nextListingId; i++) {
            if (energyListings[i].isActive) {
                activeCount++;
            }
        }
        return activeCount;
    }
    
    function calculateTotalPrice(uint256 _listingId, uint256 _energyAmount) external view returns (uint256) {
        require(_listingId > 0 && _listingId < nextListingId, "Invalid listing ID");
        EnergyListing memory listing = energyListings[_listingId];
        return (_energyAmount * listing.pricePerKWh) / ENERGY_PRECISION;
    }
    
    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    function updateOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid new owner address");
        owner = _newOwner;
    }
}
