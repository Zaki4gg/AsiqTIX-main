// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AsiqTixTickets is ERC1155, Ownable {
    struct EventConfig {
        address promoter;
        uint256 tokenId;
        uint256 priceWei;
        uint256 maxSupply;
        uint256 sold;
        bool active;
    }

    mapping(uint256 => EventConfig) public events;
    uint256 public nextEventId = 1;

    uint96 public feeBps = 1000;          // 10% (basis 10000)
    address public feeRecipient;          // wallet admin/platform

    event EventCreated(
        uint256 indexed eventId,
        address indexed promoter,
        uint256 tokenId,
        uint256 priceWei,
        uint256 maxSupply
    );

    event TicketPurchased(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 quantity,
        uint256 totalPaid,
        uint256 feeAmount,
        uint256 promoterAmount
    );

    // ⬇⬇⬇ PERHATIKAN BAGIAN INI
    constructor(address _feeRecipient, string memory baseUri)
        ERC1155(baseUri)          // constructor ERC1155
        Ownable(msg.sender)       // 👈 kirim owner awal ke Ownable (versi OZ kamu)
    {
        require(_feeRecipient != address(0), "INVALID_FEE_RECIPIENT");
        feeRecipient = _feeRecipient;
    }
    // ⬆⬆⬆

    function setFeeBps(uint96 _feeBps) external onlyOwner {
        require(_feeBps <= 2000, "FEE_TOO_HIGH"); // max 20%
        feeBps = _feeBps;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "INVALID_FEE_RECIPIENT");
        feeRecipient = _feeRecipient;
    }

    function createEvent(
        address promoter,
        uint256 tokenId,
        uint256 priceWei,
        uint256 maxSupply
    ) external onlyOwner returns (uint256 eventId) {
        require(promoter != address(0), "INVALID_PROMOTER");
        require(priceWei > 0, "PRICE_ZERO");

        eventId = nextEventId++;
        events[eventId] = EventConfig({
            promoter: promoter,
            tokenId: tokenId,
            priceWei: priceWei,
            maxSupply: maxSupply,
            sold: 0,
            active: true
        });

        emit EventCreated(eventId, promoter, tokenId, priceWei, maxSupply);
    }

    function setEventActive(uint256 eventId, bool active) external onlyOwner {
        events[eventId].active = active;
    }

    function updateEventPrice(uint256 eventId, uint256 newPriceWei)
        external
        onlyOwner
    {
        require(newPriceWei > 0, "PRICE_ZERO");
        events[eventId].priceWei = newPriceWei;
    }

    function buyTicket(uint256 eventId, uint256 quantity)
        external
        payable
    {
        require(quantity > 0, "QTY_ZERO");

        EventConfig storage cfg = events[eventId];
        require(cfg.active, "EVENT_INACTIVE");
        require(cfg.promoter != address(0), "EVENT_NOT_FOUND");

        if (cfg.maxSupply > 0) {
            require(cfg.sold + quantity <= cfg.maxSupply, "SOLD_OUT");
        }

        uint256 totalPrice = cfg.priceWei * quantity;
        require(msg.value == totalPrice, "INVALID_VALUE");

        uint256 feeAmount = (totalPrice * feeBps) / 10000;
        uint256 promoterAmount = totalPrice - feeAmount;

        cfg.sold += quantity;

        (bool sentFee, ) = feeRecipient.call{value: feeAmount}("");
        require(sentFee, "FEE_TRANSFER_FAIL");

        (bool sentPromoter, ) = cfg.promoter.call{value: promoterAmount}("");
        require(sentPromoter, "PROMOTER_TRANSFER_FAIL");

        _mint(msg.sender, cfg.tokenId, quantity, "");

        emit TicketPurchased(
            eventId,
            msg.sender,
            quantity,
            totalPrice,
            feeAmount,
            promoterAmount
        );
    }

    receive() external payable {}
}
