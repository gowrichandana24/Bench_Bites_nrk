const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const crypto = require('crypto');
const Razorpay = require('razorpay');
require('dotenv').config();

const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');
const Order = require('./models/order');
const User = require('./models/user');
const Notification = require('./models/notification');

const app = express();
const allowedStatuses = ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'];

const razorpay = new Razorpay({
  key_id: process.env.RAZORPAY_KEY_ID,
  key_secret: process.env.RAZORPAY_KEY_SECRET,
});

app.use(cors({ origin: process.env.CLIENT_ORIGIN || '*' }));
app.use(express.json({ limit: '50mb' }));

function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function makeOrderId() {
  return `NRK${Date.now()}${Math.floor(Math.random() * 900 + 100)}`;
}

function toMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

function buildCafeQuery(req) {
  const query = { active: true };
  if (req.query.search) {
    query.$text = { $search: req.query.search };
  }
  if (req.query.category) {
    query.category = req.query.category;
  }
  return query;
}

async function createOrder(req, res) {
  const {
    customerName,
    customerEmail,
    userId,
    cafeId,
    cafeteriaName,
    items,
    platformFee = 3,
    discount = 0,
    payment = {},
    location,
    notes,
  } = req.body;

  if (!customerName || !cafeteriaName || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ message: 'customerName, cafeteriaName, and items are required' });
  }

  const normalizedItems = items.map(item => ({
    menuItemId: mongoose.Types.ObjectId.isValid(item.menuItemId || item.id)
      ? item.menuItemId || item.id
      : undefined,
    name: item.name,
    qty: Number(item.qty || item.quantity || 1),
    price: Number(item.price || 0),
    image: item.image || '',
  }));

  if (normalizedItems.some(item => !item.name || item.qty < 1 || item.price < 0)) {
    return res.status(400).json({ message: 'Each order item needs name, qty, and price' });
  }

  let resolvedCafeId = cafeId;
  if (!resolvedCafeId && cafeteriaName) {
    const cafe = await Cafe.findOne({ name: cafeteriaName }).select('_id');
    resolvedCafeId = cafe?._id;
  }

  const itemTotal = toMoney(normalizedItems.reduce((sum, item) => sum + item.price * item.qty, 0));
  const total = toMoney(itemTotal + Number(platformFee) - Number(discount));

  const order = await Order.create({
    orderId: makeOrderId(),
    userId,
    customerName,
    customerEmail,
    cafeId: resolvedCafeId,
    cafeteriaName,
    items: normalizedItems,
    itemTotal,
    platformFee,
    discount,
    total,
    payment,
    location,
    notes,
  });

  // Create notification for order placement
  if (userId) {
    await Notification.create({
      userId,
      title: 'Order Placed',
      message: `Your order at ${cafeteriaName} has been placed successfully!`,
      type: 'order',
      orderId: order._id,
      items: normalizedItems.map(item => item.name),
    });
  }

  let razorpayOrder = null;
  if (payment.method === 'Online') {
    const options = {
      amount: total * 100,
      currency: 'INR',
      receipt: order.orderId,
    };
    razorpayOrder = await razorpay.orders.create(options);
  }

  res.status(201).json({ order, razorpayOrder });
}

async function connectDatabase() {
  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is missing. Add it to Backend/.env');
  }

  await mongoose.connect(process.env.MONGO_URI);
  console.log('MongoDB connected');
}

app.get('/api/health', (req, res) => {
  res.json({
    ok: true,
    service: 'nevark-food-backend',
    mongoState: mongoose.connection.readyState,
  });
});

app.post('/api/auth/google', asyncHandler(async (req, res) => {
  const { googleId, name, email, avatar } = req.body;
  if (!googleId || !name || !email) {
    return res.status(400).json({ message: 'googleId, name, and email are required' });
  }

  console.debug('POST /api/auth/google', { googleId, email });

  const filter = {
    $or: [
      { googleId },
      { email: email.toLowerCase() },
    ],
  };
  const update = {
    $set: { googleId, name, email: email.toLowerCase(), avatar },
    $setOnInsert: { role: 'customer' },
  };

  let user = await User.findOneAndUpdate(filter, update, {
    new: true,
    upsert: true,
    runValidators: true,
  }).populate('cafeId');

  if (user.role === 'vendor' && user._id && !user.cafeId) {
    const cafe = await Cafe.findOne({
      $or: [
        { vendorId: user._id },
        { legacyVendorId: user.googleId },
      ],
    });

    if (cafe) {
      console.debug('Linking vendor to cafe during login', { vendorId: user._id, cafeId: cafe._id });
      user = await User.findByIdAndUpdate(
        user._id,
        { cafeId: cafe._id },
        { new: true, runValidators: true }
      ).populate('cafeId');
    }
  }

  console.debug('Auth response user', { id: user._id.toString(), role: user.role, cafeId: user.cafeId?._id?.toString() });
  res.status(200).json(user);
}));

app.patch('/api/users/:id', asyncHandler(async (req, res) => {
  const allowed = {};
  for (const key of ['name', 'email', 'avatar', 'address', 'paymentLabel']) {
    if (req.body[key] !== undefined) allowed[key] = req.body[key];
  }

  const user = await User.findByIdAndUpdate(req.params.id, allowed, {
    new: true,
    runValidators: true,
  }).populate('cafeId');

  if (!user) return res.status(404).json({ message: 'User not found' });
  res.json(user);
}));

// ==================== VENDOR-CAFE RELATIONSHIP ENDPOINTS ====================

// Assign a cafeteria to a vendor
app.post('/api/vendors/:vendorId/assign-cafe', asyncHandler(async (req, res) => {
  const { vendorId } = req.params;
  const { cafeId } = req.body;

  if (!mongoose.Types.ObjectId.isValid(vendorId)) {
    return res.status(400).json({ message: 'Invalid vendorId' });
  }
  if (!mongoose.Types.ObjectId.isValid(cafeId)) {
    return res.status(400).json({ message: 'Invalid cafeId' });
  }

  if (!cafeId) {
    return res.status(400).json({ message: 'cafeId is required' });
  }

  const vendor = await User.findById(vendorId);
  if (!vendor) return res.status(404).json({ message: 'Vendor not found' });
  if (vendor.role !== 'vendor') {
    return res.status(403).json({ message: 'User is not a vendor' });
  }

  const cafe = await Cafe.findById(cafeId);
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });

  if (cafe.vendorId && cafe.vendorId.toString() !== vendorId) {
    return res.status(409).json({ message: 'Cafe is already assigned to another vendor' });
  }

  console.debug('POST /api/vendors/:vendorId/assign-cafe', { vendorId, cafeId });

  const updatedCafe = await Cafe.findByIdAndUpdate(
    cafeId,
    {
      vendorId: vendor._id,
      legacyVendorId: cafe.legacyVendorId || vendor.googleId || cafe.legacyVendorId,
    },
    { new: true, runValidators: true }
  ).populate('vendorId', 'name email avatar');

  const updatedUser = await User.findByIdAndUpdate(
    vendorId,
    { cafeId: cafeId },
    { new: true, runValidators: true }
  ).populate('cafeId');

  res.json({
    message: 'Vendor successfully assigned to cafeteria',
    vendor: updatedUser,
    cafe: updatedCafe,
  });
}));

// Get vendor's assigned cafeteria
app.get('/api/vendors/:vendorId/cafes', asyncHandler(async (req, res) => {
  const { vendorId } = req.params;

  if (!mongoose.Types.ObjectId.isValid(vendorId)) {
    return res.status(400).json({ message: 'Invalid vendorId' });
  }

  const vendor = await User.findById(vendorId).populate('cafeId');
  if (!vendor) return res.status(404).json({ message: 'Vendor not found' });
  if (vendor.role !== 'vendor') {
    return res.status(403).json({ message: 'User is not a vendor' });
  }

  if (vendor.cafeId) {
    return res.json({ message: 'Vendor cafeteria found', cafe: vendor.cafeId });
  }

  const cafe = await Cafe.findOne({
    $or: [
      { vendorId: vendor._id },
      { legacyVendorId: vendor.googleId },
    ],
  }).populate('vendorId', 'name email avatar');

  if (cafe) {
    console.debug('Vendor cafe linked using cafe.vendorId', { vendorId, cafeId: cafe._id });
    await User.findByIdAndUpdate(vendorId, { cafeId: cafe._id });
    return res.json({ message: 'Vendor cafeteria found', cafe });
  }

  res.json({ message: 'Vendor has no assigned cafeteria', cafe: null });
}));

// Get vendor for a specific cafeteria
app.get('/api/cafes/:cafeId/vendor', asyncHandler(async (req, res) => {
  const { cafeId } = req.params;

  if (!mongoose.Types.ObjectId.isValid(cafeId)) {
    return res.status(400).json({ message: 'Invalid cafeId' });
  }

  const cafe = await Cafe.findById(cafeId).populate('vendorId', 'name email avatar');
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });

  if (!cafe.vendorId) {
    return res.json({ message: 'Cafeteria has no assigned vendor', vendor: null });
  }

  res.json({ message: 'Vendor found for cafeteria', vendor: cafe.vendorId });
}));

// Remove vendor from cafeteria (unassign)
app.delete('/api/vendors/:vendorId/cafes/:cafeId', asyncHandler(async (req, res) => {
  const { vendorId, cafeId } = req.params;

  if (!mongoose.Types.ObjectId.isValid(vendorId)) {
    return res.status(400).json({ message: 'Invalid vendorId' });
  }
  if (!mongoose.Types.ObjectId.isValid(cafeId)) {
    return res.status(400).json({ message: 'Invalid cafeId' });
  }

  const vendor = await User.findById(vendorId);
  if (!vendor) return res.status(404).json({ message: 'Vendor not found' });

  const cafe = await Cafe.findById(cafeId);
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });

  if (cafe.vendorId?.toString() !== vendorId) {
    return res.status(403).json({ message: 'This cafeteria is not assigned to this vendor' });
  }

  console.debug('DELETE /api/vendors/:vendorId/cafes/:cafeId', { vendorId, cafeId });

  const updatedCafe = await Cafe.findByIdAndUpdate(cafeId, { vendorId: null }, { new: true, runValidators: true });
  const updatedUser = await User.findByIdAndUpdate(vendorId, { cafeId: null }, { new: true, runValidators: true });

  res.json({
    message: 'Vendor successfully unassigned from cafeteria',
    vendor: updatedUser,
    cafe: updatedCafe,
  });
}));

// ==================== END VENDOR-CAFE ENDPOINTS ====================

app.get('/api/cafes', asyncHandler(async (req, res) => {
  const cafes = await Cafe.find(buildCafeQuery(req))
    .populate('vendorId', 'name email avatar')
    .sort({ rating: -1, name: 1 });
  res.json(cafes);
}));

app.get('/api/cafes/:id', asyncHandler(async (req, res) => {
  const cafe = await Cafe.findById(req.params.id).populate('vendorId', 'name email avatar');
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  res.json(cafe);
}));

app.post('/api/cafes', asyncHandler(async (req, res) => {
  const cafe = await Cafe.create(req.body);
  const populatedCafe = await cafe.populate('vendorId', 'name email avatar');
  res.status(201).json(populatedCafe);
}));

app.patch('/api/cafes/:id', asyncHandler(async (req, res) => {
  const cafe = await Cafe.findByIdAndUpdate(req.params.id, req.body, {
    new: true,
    runValidators: true,
  }).populate('vendorId', 'name email avatar');
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  res.json(cafe);
}));

app.get('/api/menu', asyncHandler(async (req, res) => {
  const query = {};
  if (req.query.cafeId) query.cafeId = req.query.cafeId;
  
  // Support both ObjectId vendorId and legacy string vendorId
  if (req.query.vendorId) {
    if (mongoose.Types.ObjectId.isValid(req.query.vendorId)) {
      query.vendorId = req.query.vendorId;
    } else {
      query.legacyVendorId = req.query.vendorId;
    }
  }
  
  if (req.query.available !== undefined) query.available = req.query.available === 'true';
  if (req.query.search) query.$text = { $search: req.query.search };

  const items = await MenuItem.find(query)
    .populate('cafeId', 'name slug')
    .populate('vendorId', 'name email')
    .sort({ category: 1, name: 1 });
  res.json(items);
}));

app.get('/api/cafes/:id/menu', asyncHandler(async (req, res) => {
  const items = await MenuItem.find({ cafeId: req.params.id, available: true })
    .populate('vendorId', 'name email')
    .sort({ category: 1, name: 1 });
  res.json(items);
}));

// Get menu items for a vendor
app.get('/api/vendors/:vendorId/menu', asyncHandler(async (req, res) => {
  const { vendorId } = req.params;

  if (!mongoose.Types.ObjectId.isValid(vendorId)) {
    return res.status(400).json({ message: 'Invalid vendorId' });
  }

  const vendor = await User.findById(vendorId);
  if (!vendor) return res.status(404).json({ message: 'Vendor not found' });
  if (vendor.role !== 'vendor') return res.status(403).json({ message: 'User is not a vendor' });

  const query = {
    $or: [
      { vendorId: vendor._id },
      { legacyVendorId: vendor.googleId },
    ],
  };

  const items = await MenuItem.find(query)
    .populate('cafeId', 'name slug')
    .sort({ category: 1, name: 1 });

  console.debug('GET /api/vendors/:vendorId/menu', { vendorId, itemCount: items.length });

  res.json({
    message: items.isEmpty ? 'No menu items found for this vendor' : 'Menu items found',
    items,
  });
}));

app.post('/api/menu', asyncHandler(async (req, res) => {
  // If vendorId is provided as a string but cafeId exists, try to get vendor from cafe
  const item = await MenuItem.create(req.body);
  const populatedItem = await item.populate(['cafeId', 'vendorId']);
  res.status(201).json(populatedItem);
}));

app.post('/api/menu/add', asyncHandler(async (req, res) => {
  const item = await MenuItem.create(req.body);
  const populatedItem = await item.populate(['cafeId', 'vendorId']);
  res.status(201).json(populatedItem);
}));

app.patch('/api/menu/:id', asyncHandler(async (req, res) => {
  const item = await MenuItem.findByIdAndUpdate(req.params.id, req.body, {
    new: true,
    runValidators: true,
  }).populate(['cafeId', 'vendorId']);
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.json(item);
}));

app.delete('/api/menu/:id', asyncHandler(async (req, res) => {
  const item = await MenuItem.findByIdAndDelete(req.params.id);
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.status(204).send();
}));

app.post('/api/orders', asyncHandler(createOrder));
app.post('/api/orders/place', asyncHandler(createOrder));

app.get('/api/orders', asyncHandler(async (req, res) => {
  const query = {};
  if (req.query.cafeId) query.cafeId = req.query.cafeId;
  if (req.query.customerEmail) query.customerEmail = req.query.customerEmail.toLowerCase();
  if (req.query.status) query.status = req.query.status;

  const orders = await Order.find(query).sort({ createdAt: -1 });
  res.json(orders);
}));

app.get('/api/orders/:orderId', asyncHandler(async (req, res) => {
  const order = await Order.findOne({ orderId: req.params.orderId });
  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

app.patch('/api/orders/:orderId/status', asyncHandler(async (req, res) => {
  const { status } = req.body;
  if (!allowedStatuses.includes(status)) {
    return res.status(400).json({ message: `status must be one of: ${allowedStatuses.join(', ')}` });
  }

  const order = await Order.findOneAndUpdate(
    { orderId: req.params.orderId },
    { status },
    { new: true, runValidators: true }
  );

  if (!order) return res.status(404).json({ message: 'Order not found' });

  // Create notification for status update
  if (order.userId) {
    let title, message;
    switch (status) {
      case 'Preparing':
        title = 'Order Being Prepared';
        message = `Your order at ${order.cafeteriaName} is now being prepared!`;
        break;
      case 'Ready':
        title = 'Order Ready for Pickup';
        message = `Your order at ${order.cafeteriaName} is ready for pickup.`;
        break;
      case 'Completed':
        title = 'Order Completed';
        message = `Your order at ${order.cafeteriaName} has been completed. Enjoy your meal!`;
        break;
      case 'Rejected':
        title = 'Order Rejected';
        message = `Unfortunately, your order at ${order.cafeteriaName} has been rejected.`;
        break;
      default:
        title = 'Order Status Updated';
        message = `Your order at ${order.cafeteriaName} status has been updated to ${status}.`;
    }

    await Notification.create({
      userId: order.userId,
      title,
      message,
      type: 'order',
      orderId: order._id,
      items: order.items.map(item => item.name),
    });
  }

  res.json(order);
}));

app.get('/api/vendor/:vendorId/dashboard', asyncHandler(async (req, res) => {
  const cafes = await Cafe.find({ vendorId: req.params.vendorId }).select('_id');
  const cafeIds = cafes.map(cafe => cafe._id);
  const orderQuery = cafeIds.length ? { cafeId: { $in: cafeIds } } : {};

  const [summary] = await Order.aggregate([
    { $match: orderQuery },
    {
      $group: {
        _id: null,
        totalOrders: { $sum: 1 },
        revenue: { $sum: '$total' },
        activeOrders: {
          $sum: { $cond: [{ $in: ['$status', ['Pending', 'Preparing', 'Ready']] }, 1, 0] },
        },
        completed: { $sum: { $cond: [{ $eq: ['$status', 'Completed'] }, 1, 0] } },
      },
    },
  ]);

  const recentOrders = await Order.find(orderQuery).sort({ createdAt: -1 }).limit(6);
  res.json({
    totalOrders: summary?.totalOrders || 0,
    revenue: summary?.revenue || 0,
    activeOrders: summary?.activeOrders || 0,
    completed: summary?.completed || 0,
    recentOrders,
  });
}));

app.post('/api/payment/create-order', asyncHandler(async (req, res) => {
  const { amount, currency = 'INR', receipt } = req.body;

  if (!amount || amount <= 0) {
    return res.status(400).json({ message: 'Valid amount is required' });
  }

  const options = {
    amount: amount * 100, // Razorpay expects amount in paisa
    currency,
    receipt,
  };

  const order = await razorpay.orders.create(options);
  res.json(order);
}));

app.post('/api/payment/verify', asyncHandler(async (req, res) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

  const sign = razorpay_order_id + '|' + razorpay_payment_id;
  const expectedSign = crypto.createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(sign.toString())
    .digest('hex');

  if (razorpay_signature === expectedSign) {
    res.json({ message: 'Payment verified successfully' });
  } else {
    res.status(400).json({ message: 'Payment verification failed' });
  }
}));

app.patch('/api/orders/:orderId/payment', asyncHandler(async (req, res) => {
  const { transactionId, status } = req.body;

  const order = await Order.findOneAndUpdate(
    { orderId: req.params.orderId },
    { 
      'payment.transactionId': transactionId,
      'payment.status': status,
      'payment.provider': 'Razorpay'
    },
    { new: true }
  );

  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

// Notification routes
app.get('/api/notifications', asyncHandler(async (req, res) => {
  const { userId } = req.query;
  if (!userId) return res.status(400).json({ message: 'userId is required' });

  const notifications = await Notification.find({ userId })
    .sort({ createdAt: -1 })
    .populate('orderId', 'orderId cafeteriaName status');

  res.json(notifications);
}));

app.post('/api/notifications', asyncHandler(async (req, res) => {
  const { userId, title, message, type, orderId, items } = req.body;

  if (!userId || !title || !message) {
    return res.status(400).json({ message: 'userId, title, and message are required' });
  }

  const notification = await Notification.create({
    userId,
    title,
    message,
    type: type || 'system',
    orderId,
    items: items || [],
  });

  res.status(201).json(notification);
}));

app.patch('/api/notifications/:id/read', asyncHandler(async (req, res) => {
  const notification = await Notification.findByIdAndUpdate(
    req.params.id,
    { isRead: true },
    { new: true }
  );

  if (!notification) return res.status(404).json({ message: 'Notification not found' });
  res.json(notification);
}));

app.delete('/api/notifications/:id', asyncHandler(async (req, res) => {
  const notification = await Notification.findByIdAndDelete(req.params.id);
  if (!notification) return res.status(404).json({ message: 'Notification not found' });
  res.json({ message: 'Notification deleted' });
}));

app.use((req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

app.use((err, req, res, next) => {
  console.error(err);
  if (err.name === 'ValidationError') {
    return res.status(400).json({ message: err.message });
  }
  if (err.code === 11000) {
    return res.status(409).json({ message: 'Duplicate value', fields: err.keyValue });
  }
  res.status(500).json({ message: 'Internal server error' });
});

const PORT = process.env.PORT || 5000;

connectDatabase()
  .then(() => app.listen(PORT, () => console.log(`Server running on port ${PORT}`)))
  .catch(err => {
    console.error('Failed to start server:', err.message);
    process.exit(1);
  });
