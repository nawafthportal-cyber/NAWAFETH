# Nawafeth Flutter Mobile App — Complete Analysis for Web Frontend Rebuild

> **Purpose**: 1:1 web frontend rebuild reference  
> **Source**: `mobile/lib/` — every file analyzed  
> **Backend API Base**: `https://nawafeth-2290.onrender.com`

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Configuration & Constants](#2-configuration--constants)
3. [Routing & Navigation](#3-routing--navigation)
4. [Authentication Flow](#4-authentication-flow)
5. [Services — Complete API Endpoint Inventory](#5-services--complete-api-endpoint-inventory)
6. [Models — Complete Field Inventory](#6-models--complete-field-inventory)
7. [Screens — Full Inventory with API Calls & UI Components](#7-screens--full-inventory)
8. [Widgets — Reusable Components](#8-widgets--reusable-components)
9. [Dual-Mode Architecture (Client / Provider)](#9-dual-mode-architecture)
10. [Theme & Styling](#10-theme--styling)

---

## 1. Architecture Overview

| Aspect | Detail |
|--------|--------|
| **Framework** | Flutter (Dart) |
| **State Management** | `setState` + `InheritedWidget` (`MyThemeController`) |
| **HTTP Client** | Custom `ApiClient` wrapper around `dart:io HttpClient` (not `package:http`) |
| **Auth Storage** | `SharedPreferences` (access_token, refresh_token, user_id, role_state) |
| **Locale** | Arabic RTL (`ar_SA`), Cairo font throughout |
| **Dual Mode** | Client vs Provider — toggled via `AccountModeService`, affects API `?mode=` param and UI visibility |
| **Media** | `video_player`, `flutter_image_compress`, `image_picker`, `file_picker`, `flutter_sound` (audio recording) |
| **Maps** | `flutter_map` + `latlong2` + `geolocator` |
| **Other Packages** | `flutter_rating_bar`, `font_awesome_flutter`, `animate_do`, `intl`, `shared_preferences` |

### File Structure

```
lib/
├── main.dart                          # App entry, routing, theme
├── constants/
│   ├── app_env.dart                   # API base URL config
│   ├── app_texts.dart                 # Bilingual translations (ar/en)
│   ├── colors.dart                    # Theme colors
│   └── saudi_cities.dart              # 76 Saudi cities list
├── services/                          # 18+ service files — all API calls
├── models/                            # 14 model files — all data shapes
├── screens/                           # 40+ screen files
│   ├── provider_dashboard/            # Provider-only screens
│   └── registration_steps/            # Provider registration wizard
├── widgets/                           # 13 reusable widget files
└── utils/
    └── debounced_save_runner.dart      # Debounce utility
```

---

## 2. Configuration & Constants

### `app_env.dart` — API Base URL

```dart
class AppEnv {
  static const String renderBase = 'https://nawafeth-2290.onrender.com';
  // Local targets vary by platform (Android emulator: 10.0.2.2, iOS sim: 127.0.0.1, etc.)
  static String apiBase = renderBase; // default
  static ApiTarget currentTarget = ApiTarget.render;
}
enum ApiTarget { local, render, auto }
```

### `colors.dart` — Theme Colors

| Name | Value | Usage |
|------|-------|-------|
| `background` | `#FFFFFF` | Page backgrounds |
| `softBlue` | `#E8F0FE` | Card tints |
| `accentOrange` | `#FF9800` | Accent / CTAs |
| `lightPurple` | `#E6E6FA` | Soft highlight |
| `deepPurple` | `#663D90` | **Primary brand color** |
| `primaryDark` | — | Dark variant of primary |
| `primaryLight` | `#E6E6FA` | Light variant of primary |

### `saudi_cities.dart`

Static list of 76 Saudi city names in Arabic alphabetical order. Used in city dropdowns (signup, provider profile, request forms).

### `app_texts.dart` — Bilingual Labels

Drawer/menu labels in Arabic & English: الرئيسية/Home, طلباتي/My Orders, المحادثات/Chats, التفاعلات/Interactive, ملفي/My Profile, الإعدادات/Settings, اللغة/Language, رمز QR/QR Code, الشروط والأحكام/Terms & Conditions, الدعم الفني/Support, عن نوافذ/About Nawafeth.

---

## 3. Routing & Navigation

### Named Routes (main.dart)

| Route | Screen | Mode Guard |
|-------|--------|------------|
| `/onboarding` | `OnboardingScreen` | — |
| `/home` | `HomeScreen` | — |
| `/chats` | `MyChatsScreen` | — |
| `/orders` | `OrdersHubScreen` | — |
| `/interactive` | `InteractiveScreen` | — |
| `/profile` | `MyProfileScreen` | — |
| `/add_service` | `AddServiceScreen` | **Client only** |
| `/login` | `LoginScreen` | — |
| `/search_provider` | `SearchProviderScreen` | **Client only** |
| `/urgent_request` | `UrgentRequestScreen` | **Client only** |
| `/request_quote` | `RequestQuoteScreen` | **Client only** |

**Initial route**: `/onboarding`

**Mode Guard**: `_ModeRouteGuard` widget checks `AccountModeService.isProviderMode` — if true and route is client-only, redirects to `/home`.

### Bottom Navigation Bar

5 tabs: **Home** (`/home`), **Orders** (`/orders`), **+ Add Service FAB** (`/add_service`), **Interactive** (`/interactive`), **Profile** (`/profile`).

- In provider mode, "طلباتي" label is hidden and "طلبات الخدمة" shown instead
- Floating center button for add service

### Drawer Navigation

Side drawer with: Home, Settings, Language (ar/en toggle), QR Code, Terms & Conditions, Contact Support, About Nawafeth, Theme Toggle (light/dark), Logout, Delete Account.

---

## 4. Authentication Flow

```
Phone Input → Send OTP → Verify OTP → JWT Tokens
                                         ↓
                              role_state == "phone_only"?
                              ├─ YES → Signup Screen (complete registration)
                              └─ NO  → Home Screen
```

| Step | API | Details |
|------|-----|---------|
| Send OTP | `POST /api/accounts/otp/send/` | Body: `{ phone }` |
| Verify OTP | `POST /api/accounts/otp/verify/` | Body: `{ phone, code }` → returns `{ access, refresh, user_id, role_state }` |
| Complete Registration | `POST /api/accounts/complete/` | Body: `{ first_name, last_name, username, email, city, password, password_confirm }` |
| Check Username | `GET /api/accounts/username-availability/?username=` | Live check during signup |
| Token Refresh | `POST /api/accounts/token/refresh/` | Body: `{ refresh }` → new `{ access }` |
| Logout | `POST /api/accounts/logout/` | Body: `{ refresh_token }` |
| Delete Account | `DELETE /api/accounts/delete/` | Requires auth |

**Guest Mode**: Users can skip login and browse home screen with limited functionality. `AuthService.logout()` clears tokens and navigates to `/home`.

---

## 5. Services — Complete API Endpoint Inventory

### 5.1 `ApiClient` (Base HTTP Client)

- Singleton pattern with auto-auth headers (`Authorization: Bearer <token>`)
- Auto token refresh on 401 response
- Methods: `get()`, `post()`, `patch()`, `put()`, `delete()`, `sendMultipart()`
- Timeout: 25 seconds
- `buildMediaUrl(path)` — resolves relative media paths to full URLs

### 5.2 `AuthApiService`

| Method | Endpoint | Body/Params |
|--------|----------|-------------|
| `sendOtp(phone)` | `POST /api/accounts/otp/send/` | `{ phone }` |
| `verifyOtp(phone, code)` | `POST /api/accounts/otp/verify/` | `{ phone, code }` → `{ access, refresh, user_id, role_state }` |
| `checkUsernameAvailability(username)` | `GET /api/accounts/username-availability/?username=` | — |
| `completeRegistration(data)` | `POST /api/accounts/complete/` | `{ first_name, last_name, username, email, city, password, password_confirm }` |

### 5.3 `AuthService` (Local Storage)

| Method | Storage Key |
|--------|-------------|
| `saveTokens(access, refresh)` | `access_token`, `refresh_token` |
| `getAccessToken()` | `access_token` |
| `getRefreshToken()` | `refresh_token` |
| `saveUserId(id)` | `user_id` |
| `getUserId()` | `user_id` |
| `saveRoleState(state)` | `role_state` |
| `getRoleState()` | `role_state` |
| `isLoggedIn()` | checks `access_token` exists |
| `logout()` | clears all keys |

### 5.4 `AccountModeService`

| Method | Detail |
|--------|--------|
| `isProviderMode` | `SharedPreferences` bool key `isProvider` |
| `setProviderMode(bool)` | Saves to SharedPreferences |
| `apiMode` | Returns `'provider'` or `'client'` string |

### 5.5 `HomeService` (2-minute cache)

| Method | Endpoint | Returns |
|--------|----------|---------|
| `fetchCategories()` | `GET /api/providers/categories/` | `List<CategoryModel>` |
| `fetchFeaturedProviders(pageSize)` | `GET /api/providers/list/?page_size=` | `List<ProviderPublicModel>` |
| `fetchHomeBanners(limit)` | `GET /api/promo/banners/home/?limit=` | `List<BannerModel>` |
| `fetchSpotlightFeed(limit)` | `GET /api/providers/spotlights/feed/?limit=` | `List<MediaItemModel>` |

### 5.6 `ProfileService`

| Method | Endpoint | Body |
|--------|----------|------|
| `fetchMyProfile()` | `GET /api/accounts/me/` | → `UserProfile` |
| `updateMyProfile(data)` | `PATCH /api/accounts/me/` | JSON fields |
| `uploadMyProfileImages(profileFile?, coverFile?)` | `PATCH /api/accounts/me/` | Multipart (profile_image, cover_image) |
| `fetchProviderProfile()` | `GET /api/providers/me/profile/` | → `ProviderProfileModel` |
| `updateProviderProfile(data)` | `PATCH /api/providers/me/profile/` | JSON fields |
| `uploadProviderProfileImages(profileFile?, coverFile?)` | `PATCH /api/providers/me/profile/` | Multipart |
| `uploadProviderPortfolioItem(file, caption?, fileType?)` | `POST /api/providers/me/portfolio/` | Multipart |
| `uploadProviderSpotlight(file, caption?, fileType?)` | `POST /api/providers/me/spotlights/` | Multipart |
| `registerProvider(data)` | `POST /api/providers/register/` | JSON provider data |
| `getWallet()` | `GET /api/accounts/wallet/` | Wallet balance info |

### 5.7 `MarketplaceService` (367 lines — most complex service)

**Client-side:**

| Method | Endpoint | Details |
|--------|----------|---------|
| `getCategories()` | `GET /api/providers/categories/` | |
| `createRequest(data)` | `POST /api/marketplace/requests/create/` | Multipart: title, description, request_type (normal/competitive/urgent), city, category_id, subcategory_id, images[], videos[], files[], audio |
| `getClientRequests(statusGroup?, type?, query?)` | `GET /api/marketplace/client/requests/?status_group=&type=&q=` | |
| `getClientRequestDetail(id)` | `GET /api/marketplace/client/requests/{id}/` | → `ServiceRequest` |
| `updateClientRequest(id, data)` | `PATCH /api/marketplace/client/requests/{id}/` | |
| `cancelRequest(id)` | `POST /api/marketplace/requests/{id}/cancel/` | |
| `reopenRequest(id)` | `POST /api/marketplace/requests/{id}/reopen/` | |
| `getRequestOffers(requestId)` | `GET /api/marketplace/requests/{id}/offers/` | → `List<Offer>` |
| `acceptOffer(offerId)` | `POST /api/marketplace/offers/{id}/accept/` | |

**Provider-side:**

| Method | Endpoint | Details |
|--------|----------|---------|
| `getProviderRequests(statusGroup?, clientUserId?)` | `GET /api/marketplace/provider/requests/?status_group=&client_user_id=` | |
| `getProviderRequestDetail(id)` | `GET /api/marketplace/provider/requests/{id}/detail/` | → `ProviderOrder` |
| `acceptRequest(id)` | `POST /api/marketplace/provider/requests/{id}/accept/` | |
| `rejectRequest(id)` | `POST /api/marketplace/provider/requests/{id}/reject/` | |
| `startRequest(id)` | `POST /api/marketplace/requests/{id}/start/` | |
| `updateProgress(id, data)` | `POST /api/marketplace/provider/requests/{id}/progress-update/` | |
| `completeRequest(id)` | `POST /api/marketplace/requests/{id}/complete/` | |
| `getAvailableUrgentRequests()` | `GET /api/marketplace/provider/urgent/available/` | |
| `acceptUrgentRequest(data)` | `POST /api/marketplace/requests/urgent/accept/` | |
| `getCompetitiveRequests()` | `GET /api/marketplace/provider/competitive/available/` | |
| `createOffer(requestId, data)` | `POST /api/marketplace/requests/{id}/offers/create/` | |

### 5.8 `MessagingService`

| Method | Endpoint | Details |
|--------|----------|---------|
| `fetchThreads(mode)` | `GET /api/messaging/direct/threads/?mode=` | → `List<ChatThread>` |
| `fetchThreadStates(mode)` | `GET /api/messaging/threads/states/?mode=` | → `List<ThreadState>` |
| `getOrCreateDirectThread(peerId, peerProviderId?, mode?)` | `POST /api/messaging/direct/thread/` | Body: `{ peer_id, peer_provider_id }` |
| `fetchMessages(threadId, limit?, offset?)` | `GET /api/messaging/direct/thread/{id}/messages/?limit=&offset=` | → `List<ChatMessageModel>` |
| `sendTextMessage(threadId, body)` | `POST /api/messaging/direct/thread/{id}/messages/send/` | Body: `{ body }` |
| `sendAttachment(threadId, file, type)` | `POST /api/messaging/direct/thread/{id}/messages/send/` | Multipart: attachment + attachment_type (audio/image/file) |
| `markRead(threadId)` | `POST /api/messaging/direct/thread/{id}/messages/read/` | |
| `toggleUnread(threadId)` | `POST /api/messaging/thread/{id}/unread/` | |
| `toggleFavorite(threadId)` | `POST /api/messaging/thread/{id}/favorite/` | |
| `toggleBlock(threadId)` | `POST /api/messaging/thread/{id}/block/` | |
| `toggleArchive(threadId)` | `POST /api/messaging/thread/{id}/archive/` | |
| `reportThread(threadId, data)` | `POST /api/messaging/thread/{id}/report/` | Body: `{ reason, details }` |
| `deleteMessage(threadId, messageId)` | `POST /api/messaging/thread/{id}/messages/{mid}/delete/` | |

### 5.9 `InteractiveService` (Social/Engagement)

**Follow/Unfollow:**

| Method | Endpoint |
|--------|----------|
| `fetchFollowing(mode)` | `GET /api/providers/me/following/?mode=` |
| `fetchFollowers()` | `GET /api/providers/me/followers/` |
| `followProvider(id, mode)` | `POST /api/providers/{id}/follow/?mode=` |
| `unfollowProvider(id, mode)` | `POST /api/providers/{id}/unfollow/?mode=` |
| `fetchProviderFollowers(id, mode)` | `GET /api/providers/{id}/followers/?mode=` |
| `fetchProviderFollowing(id, mode)` | `GET /api/providers/{id}/following/?mode=` |

**Favorites:**

| Method | Endpoint |
|--------|----------|
| `fetchFavorites(mode)` | `GET /api/providers/me/favorites/?mode=` |
| `fetchFavoriteSpotlights(mode)` | `GET /api/providers/me/favorites/spotlights/?mode=` |
| `unsavePortfolioItem(id, mode)` | `POST /api/providers/portfolio/{id}/unsave/?mode=` |
| `unsaveSpotlight(id, mode)` | `POST /api/providers/spotlights/{id}/unsave/?mode=` |

**Portfolio/Spotlights:**

| Method | Endpoint |
|--------|----------|
| `fetchMyPortfolio()` | `GET /api/providers/me/portfolio/` |
| `fetchMySpotlights()` | `GET /api/providers/me/spotlights/` |
| `fetchProviderPortfolio(id)` | `GET /api/providers/{id}/portfolio/` |
| `fetchProviderSpotlights(id)` | `GET /api/providers/{id}/spotlights/` |
| `deletePortfolioItem(id)` | `DELETE /api/providers/me/portfolio/{id}/` |
| `deleteSpotlightItem(id)` | `DELETE /api/providers/me/spotlights/{id}/` |

**Like/Unlike/Save:**

| Method | Endpoint |
|--------|----------|
| `likePortfolio(id, mode)` | `POST /api/providers/portfolio/{id}/like/?mode=` |
| `unlikePortfolio(id, mode)` | `POST /api/providers/portfolio/{id}/unlike/?mode=` |
| `savePortfolio(id, mode)` | `POST /api/providers/portfolio/{id}/save/?mode=` |
| `likeSpotlight(id, mode)` | `POST /api/providers/spotlights/{id}/like/?mode=` |
| `unlikeSpotlight(id, mode)` | `POST /api/providers/spotlights/{id}/unlike/?mode=` |
| `saveSpotlight(id, mode)` | `POST /api/providers/spotlights/{id}/save/?mode=` |
| `unsaveSpotlight(id, mode)` | `POST /api/providers/spotlights/{id}/unsave/?mode=` |
| `likeProvider(id, mode)` | `POST /api/providers/{id}/like/?mode=` |
| `unlikeProvider(id, mode)` | `POST /api/providers/{id}/unlike/?mode=` |

**Provider Profile:**

| Method | Endpoint |
|--------|----------|
| `fetchProviderDetail(id)` | `GET /api/providers/{id}/` |
| `fetchProviderServices(id)` | `GET /api/providers/{id}/services/` |
| `fetchProviderStats(id)` | `GET /api/providers/{id}/stats/` |

### 5.10 `NotificationService`

| Method | Endpoint |
|--------|----------|
| `fetchNotifications(limit, offset, mode)` | `GET /api/notifications/?limit=&offset=&mode=` |
| `fetchUnreadCount(mode)` | `GET /api/notifications/unread-count/?mode=` |
| `markRead(id, mode)` | `POST /api/notifications/mark-read/{id}/?mode=` |
| `markAllRead(mode)` | `POST /api/notifications/mark-all-read/?mode=` |
| `pinNotification(id, mode)` | `POST /api/notifications/actions/{id}/?mode=` body: `{ action: "pin" }` |
| `followUpNotification(id, mode)` | `POST /api/notifications/actions/{id}/?mode=` body: `{ action: "follow_up" }` |
| `removeAction(id, mode)` | `DELETE /api/notifications/actions/{id}/?mode=` |
| `fetchPreferences(mode)` | `GET /api/notifications/preferences/?mode=` |
| `updatePreferences(mode, data)` | `PATCH /api/notifications/preferences/?mode=` |
| `registerDeviceToken(token)` | `POST /api/notifications/device-token/` |
| `deleteOld(mode)` | `POST /api/notifications/delete-old/?mode=` |

### 5.11 `BillingService`

| Method | Endpoint |
|--------|----------|
| `fetchInvoices()` | `GET /api/billing/invoices/my/` |
| `fetchInvoiceDetail(id)` | `GET /api/billing/invoices/{id}/` |
| `initPayment(invoiceId)` | `POST /api/billing/invoices/{id}/init-payment/` |

### 5.12 `SubscriptionsService`

| Method | Endpoint |
|--------|----------|
| `getPlans()` | `GET /api/subscriptions/plans/` |
| `mySubscriptions()` | `GET /api/subscriptions/my/` |
| `subscribe(planId)` | `POST /api/subscriptions/subscribe/{planId}/` |

### 5.13 `ReviewsService`

| Method | Endpoint |
|--------|----------|
| `submitReview(requestId, data)` | `POST /api/reviews/requests/{id}/review/` |
| `fetchProviderReviews(providerId)` | `GET /api/reviews/providers/{id}/reviews/` |
| `fetchProviderRating(providerId)` | `GET /api/reviews/providers/{id}/rating/` |
| `replyToReview(reviewId, body)` | `POST /api/reviews/reviews/{id}/provider-reply/` |

### 5.14 `SupportService`

| Method | Endpoint |
|--------|----------|
| `fetchTeams()` | `GET /api/support/teams/` |
| `createTicket(data)` | `POST /api/support/tickets/create/` |
| `fetchMyTickets(status?, type?)` | `GET /api/support/tickets/my/?status=&type=` |
| `fetchTicketDetail(id)` | `GET /api/support/tickets/{id}/` |
| `addComment(ticketId, body)` | `POST /api/support/tickets/{id}/comments/` |
| `uploadAttachment(ticketId, file)` | `POST /api/support/tickets/{id}/attachments/` (multipart) |

### 5.15 `VerificationService`

| Method | Endpoint |
|--------|----------|
| `createRequest(data)` | `POST /api/verification/requests/create/` |
| `fetchMyRequests()` | `GET /api/verification/requests/my/` |
| `fetchRequestDetail(id)` | `GET /api/verification/requests/{id}/` |
| `uploadDocument(requestId, file, docType)` | `POST /api/verification/requests/{id}/documents/` (multipart) |

### 5.16 `PromoService`

| Method | Endpoint |
|--------|----------|
| `createRequest(data)` | `POST /api/promo/requests/create/` |
| `fetchMyRequests()` | `GET /api/promo/requests/my/` |
| `fetchRequestDetail(id)` | `GET /api/promo/requests/{id}/` |
| `uploadAsset(requestId, file, ...)` | `POST /api/promo/requests/{id}/assets/` (multipart) |

### 5.17 `ExtrasService`

| Method | Endpoint |
|--------|----------|
| `fetchCatalog()` | `GET /api/extras/catalog/` |
| `fetchMyExtras()` | `GET /api/extras/my/` |
| `buy(sku)` | `POST /api/extras/buy/{sku}/` |

### 5.18 `FeaturesService`

| Method | Endpoint |
|--------|----------|
| `fetchMyFeatures()` | `GET /api/features/my/` |

### 5.19 `ContentService`

| Method | Endpoint |
|--------|----------|
| `fetchPublicContent()` | `GET /api/content/public/` |

### 5.20 `ProviderServicesService`

| Method | Endpoint |
|--------|----------|
| `fetchMyServices()` | `GET /api/providers/me/services/` |
| `createService(data)` | `POST /api/providers/me/services/` |
| `updateService(id, data)` | `PATCH /api/providers/me/services/{id}/` |
| `deleteService(id)` | `DELETE /api/providers/me/services/{id}/` |
| `fetchCategories()` | `GET /api/providers/categories/` |

### 5.21 Additional Direct API Calls (found in screens)

| Location | Endpoint |
|----------|----------|
| Drawer logout | `POST /api/accounts/logout/` body: `{ refresh_token }` |
| Drawer delete account | `DELETE /api/accounts/delete/` |
| Provider subcategories | `GET /api/providers/me/subcategories/` |
| Search provider screen | `GET /api/providers/list/?search=&category=&page_size=` |
| Providers map screen | `GET /api/providers/list/?search=&category=&lat=&lng=&radius=&page_size=` |

---

## 6. Models — Complete Field Inventory

### 6.1 `UserProfile`

```
id, phone, email, username, firstName, lastName,
profileImage, coverImage, roleState, hasProviderProfile,
isProvider, followingCount, likesCount, favoritesMediaCount,
providerProfileId, providerDisplayName, providerCity,
providerFollowersCount, providerLikesReceivedCount,
providerRatingAvg, providerRatingCount
```

### 6.2 `ProviderProfileModel` (editable — own profile)

```
id, providerType, displayName, profileImage, coverImage,
bio, aboutDetails, yearsExperience, whatsapp, website,
socialLinks[], languages[], city, lat, lng, coverageRadiusKm,
qualifications[], experiences[], contentSections[],
seoKeywords, seoMetaDescription, seoSlug,
acceptsUrgent, isVerifiedBlue, isVerifiedGreen,
ratingAvg, ratingCount
```

**Profile Completion Calculation**: 30% base + 70% across 6 optional sections (bio, qualifications, experiences, about, content, SEO).

### 6.3 `ProviderPublicModel` (read-only — public view)

```
id, displayName, username, profileImage, coverImage,
bio, aboutDetails, yearsExperience, phone, whatsapp, website,
socialLinks[], languages[], city, lat, lng, coverageRadiusKm,
acceptsUrgent, isVerifiedBlue, isVerifiedGreen,
qualifications[], ratingAvg, ratingCount,
followersCount, likesCount, followingCount, completedRequests
```

### 6.4 `UserPublicModel`

```
id, username, displayName, providerId
```

### 6.5 `CategoryModel`

```
id, name, subcategories: [SubCategoryModel(id, name)]
```

### 6.6 `ServiceRequest` (Client-side order model)

```
id, clientId, title, description,
requestType (normal|competitive|urgent),
status, statusGroup, statusLabel,
city, createdAt, expectedDeliveryAt,
providerId, providerDisplayName, providerUsername,
providerProfileImage, providerPhone,
deliveredAt, completedAt, canceledAt, cancelReason,
serviceAmountSR, receivedAmountSR, remainingAmountSR,
actualServiceAmountSR,
providerInputs: { estimatedCost, estimatedDuration, notes },
review: { rating (6 criteria: quality, speed, communication, commitment, value, overall), comment },
categoryId, categoryName, subcategoryId, subcategoryName,
clientName, clientPhone, clientCity,
attachments: [RequestAttachment(id, fileUrl, fileType, fileName)],
statusLogs: [StatusLog(status, label, createdAt, note)]
```

**Nested**: `Offer { id, providerId, providerName, providerImage, amount, duration, notes, createdAt, status }`

### 6.7 `ClientOrder` (Simplified client order)

```
id, serviceCode, createdAt, status, title, details,
attachments[], expectedDeliveryAt,
serviceAmountSR, receivedAmountSR, remainingAmountSR,
deliveredAt, actualServiceAmountSR,
ratingQuality, ratingSpeed, ratingCommunication,
ratingCommitment, ratingValueForMoney, ratingOverall,
ratingComment, canceledAt, cancelReason
```

### 6.8 `ProviderOrder` (Provider-side order model)

```
id, serviceCode, createdAt, status,
clientName, clientHandle, clientPhone, clientCity,
title, details, attachments[],
expectedDeliveryAt, deliveredAt,
serviceAmountSR, receivedAmountSR, remainingAmountSR,
actualServiceAmountSR, canceledAt, cancelReason
```

### 6.9 `ChatThread`

```
threadId, peerId, peerProviderId, peerName, peerPhone,
lastMessage, lastMessageAt, unreadCount,
isFavorite, isArchived, isBlocked,
favoriteLabel, clientLabel
```

**ThreadState**: `threadId, isFavorite, favoriteLabel, clientLabel, isArchived, isBlocked`

### 6.10 `ChatMessageModel`

```
id, senderId, senderPhone, body,
attachmentUrl, attachmentType (audio|image|file), attachmentName,
createdAt, readByIds[]
```

### 6.11 `NotificationModel`

```
id, title, body, kind, url, audienceMode,
isRead, isPinned, isFollowUp, isUrgent, createdAt
```

**NotificationPreference**: `key, title, enabled, tier, locked, updatedAt`

### 6.12 `BannerModel`

```
id, providerId, providerDisplayName, providerUsername,
fileType (image|video), fileUrl, caption, redirectUrl, createdAt
```

### 6.13 `MediaItemModel` (Portfolio & Spotlight items)

```
id, providerId, providerDisplayName, providerUsername,
providerProfileImage, fileType (image|video),
fileUrl, thumbnailUrl, caption,
likesCount, savesCount, isLiked, isSaved,
createdAt, source (portfolio|spotlight)
```

### 6.14 `TicketModel`

```
serverId, id/code, createdAt, status, supportTeam, ticketType,
title, description, priority,
attachments[], replies: [TicketReply(id, author, body, createdAt)],
lastUpdate
```

### 6.15 `ServiceProviderLocation` (Map markers)

```
id, name, category, subCategory, latitude, longitude,
rating, operationsCount, isAvailable, isUrgentEnabled,
profileImage, distanceFromUser, phoneNumber,
urgentServices[], responseTime, verified
```

---

## 7. Screens — Full Inventory

### 7.1 Onboarding & Auth

#### `onboarding_screen.dart` (212 lines)
- **Purpose**: 3-page intro slider shown on first launch
- **API Calls**: None
- **UI**: PageView with 3 slides (image + title + subtitle), dot indicator, skip button, "ابدأ الآن" (Start Now) button
- **Navigation**: → `/home`

#### `login_screen.dart` (269 lines)
- **Purpose**: Phone number input for OTP login
- **API Calls**: `AuthApiService.sendOtp(phone)`
- **UI**: Phone input with +966 prefix, "أرسل رمز التحقق" button, "تصفح كضيف" (Browse as Guest) link
- **Navigation**: → `TwoFaScreen` on success; Guest → `AuthService.logout()` then `/home`

#### `twofa_screen.dart` (437 lines)
- **Purpose**: OTP code verification
- **API Calls**: `AuthApiService.verifyOtp(phone, code)`, `AuthApiService.sendOtp(phone)` (resend)
- **UI**: 6-digit code input fields, countdown timer (60s) for resend, verify button
- **Navigation**: → `/home` if role_state != phone_only; → `SignupScreen` if phone_only

#### `signup_screen.dart` (698 lines)
- **Purpose**: Complete registration after OTP verify (for new users)
- **API Calls**: `AuthApiService.checkUsernameAvailability(username)`, `AuthApiService.completeRegistration(data)`
- **UI**: Form with: first name, last name, username (live availability check with debounce), email, city dropdown (SaudiCities list), password + confirm (with strength indicator showing 5 rules), terms checkbox
- **Validation**: Min 8 chars, uppercase, lowercase, digit, special char
- **Navigation**: → `/home`

---

### 7.2 Home & Discovery

#### `home_screen.dart` (821 lines)
- **Purpose**: Main landing page — hub for all features
- **API Calls**: `HomeService.fetchCategories()`, `fetchFeaturedProviders(10)`, `fetchHomeBanners(10)`, `fetchSpotlightFeed(20)`
- **UI Components** (top to bottom):
  1. Hero header with video background (`assets/videos/V16.mp4`), search bar overlay
  2. Categories horizontal scroll + "عرض الكل" (View All)
  3. Auto-scrolling spotlight/reels row (horizontal, TikTok-style thumbnails)
  4. Featured providers horizontal cards
  5. Promo banners carousel
  6. Quick action cards (Urgent Request, Search Provider, Request Quote)
- **Features**: Pull-to-refresh, cached data seeding, enters spotlight viewer on tap
- **Navigation**: Categories → `SearchProviderScreen`, Providers → `ProviderProfileScreen`, Spotlights → `SpotlightViewerPage`, Actions → respective screens

#### `add_service_screen.dart` (336 lines)
- **Purpose**: Hub for client service actions (client-only mode)
- **API Calls**: `HomeService.fetchCategories()`, `AuthService.isLoggedIn()`
- **UI**: 4 quick-action cards in grid:
  1. 🔍 ابحث عن مقدم خدمة (Search Provider) → `SearchProviderScreen`
  2. ⚡ طلب عاجل (Urgent Request) → `UrgentRequestScreen`
  3. 📋 طلب عرض سعر (Request Quote) → `RequestQuoteScreen`
  4. 🗺️ خريطة المزودين (Providers Map) → `ProvidersMapScreen`
- Login required check before actions

#### `search_provider_screen.dart` (497 lines)
- **Purpose**: Search/browse providers with filters
- **API Calls**: `HomeService.fetchCategories()`, `ApiClient.get('/api/providers/list/?search=&category=&page_size=')`
- **UI**: Search text field, category filter chips, results grid (provider cards with image, name, rating, city), empty state
- **Navigation**: Card tap → `ProviderProfileScreen`

#### `search_screen.dart` (284 lines)
- **Purpose**: Quick competitive request form (simplified)
- **API Calls**: `HomeService.fetchCategories()`
- **UI**: Category/subcategory dropdowns, title, details, delivery option, submit
- **Navigation**: Submit → `ServiceRequestFormScreen` (with pre-filled data)

#### `providers_map_screen.dart` (1395 lines)
- **Purpose**: Map-based provider discovery with geolocation
- **API Calls**: `HomeService.fetchCategories()`, `ApiClient.get('/api/providers/list/?search=&category=&lat=&lng=&radius=&page_size=')`
- **UI**: Full-screen `FlutterMap` with OpenStreetMap tiles, category filter bar, search field, provider markers on map, bottom sheet cards on marker tap (WhatsApp, chat, call, profile buttons)
- **Features**: Geolocator for current position, search by area, zoom controls, provider detail cards
- **Dependencies**: `flutter_map`, `latlong2`, `geolocator`, `url_launcher`

---

### 7.3 Service Requests & Orders

#### `service_request_form_screen.dart` (703 lines)
- **Purpose**: Full service request creation form (all types: normal, competitive, urgent)
- **API Calls**: `MarketplaceService.getCategories()`, `MarketplaceService.createRequest(data)` (multipart)
- **UI**: Multi-section form:
  1. Request type selector (normal/competitive/urgent)
  2. Category + subcategory dropdowns
  3. Title + description fields
  4. City dropdown
  5. Attachments section: images (image_picker), videos, files (file_picker), audio recording (flutter_sound)
  6. Submit button
- **Attachment handling**: Images compressed via `UploadOptimizer`, audio via `FlutterSoundRecorder`

#### `urgent_request_screen.dart` (506 lines)
- **Purpose**: Dedicated urgent request form (simplified)
- **API Calls**: `AccountModeService.isProviderMode`, `HomeService.fetchCategories()`, `MarketplaceService.createRequest(requestType: 'urgent')`
- **UI**: Similar to service_request_form but pre-set to urgent, with urgency notice banner

#### `request_quote_screen.dart` (517 lines)
- **Purpose**: Dedicated competitive/quote request form
- **API Calls**: `AccountModeService.isProviderMode`, `HomeService.fetchCategories()`, `MarketplaceService.createRequest(requestType: 'competitive')`
- **UI**: Similar to service_request_form but pre-set to competitive, with quote explanation

#### `orders_hub_screen.dart` (57 lines)
- **Purpose**: Router — shows client or provider orders based on current mode
- **API Calls**: `AccountModeService.isProviderMode`
- **Logic**: `isProvider ? ProviderOrdersScreen() : ClientOrdersScreen()`

#### `client_orders_screen.dart` (471 lines)
- **Purpose**: Client's order list with filtering
- **API Calls**: `AccountModeService.isProviderMode`, `MarketplaceService.getClientRequests(statusGroup, type, query)`
- **UI**: Tab bar filters (الكل/جديدة/قيد التنفيذ/مكتملة/ملغاة), search text field, order cards list (title, status badge, date, provider info)
- **Navigation**: Card tap → `ClientOrderDetailsScreen`

#### `client_order_details_screen.dart` (940 lines)
- **Purpose**: Full client order detail with actions
- **API Calls**: `MarketplaceService.getClientRequestDetail(id)`, `MarketplaceService.updateClientRequest(id, data)`, `ReviewsService.submitReview(id, data)`, `MarketplaceService.cancelRequest(id)`, `MarketplaceService.reopenRequest(id)`, `MarketplaceService.getRequestOffers(id)`, `MarketplaceService.acceptOffer(offerId)`
- **UI Components**:
  1. Status header with colored badge
  2. Editable title/details (when status = new)
  3. Provider info card (if assigned)
  4. Attachments gallery
  5. Status timeline (from statusLogs)
  6. Financial summary (amounts)
  7. Offers list (for competitive requests) with accept buttons
  8. Rating form (6 criteria sliders + comment) — shown when completed
  9. Action buttons (Cancel, Reopen based on status)
- **Rating criteria**: quality, speed, communication, commitment, valueForMoney, overall (each 1-5 stars)

#### `provider_orders_screen.dart` (372 lines)
- **Purpose**: Provider's incoming orders with tab filters
- **API Calls**: `AccountModeService.isProviderMode`, `MarketplaceService.getProviderRequests(statusGroup)`
- **UI**: Tab filters (all/new/in_progress/completed/cancelled), order cards with client info
- **Navigation**: Card tap → `ProviderOrderDetailsScreen`

#### `provider_order_details_screen.dart` (999 lines)
- **Purpose**: Provider order detail with workflow actions
- **API Calls**: `MarketplaceService.getProviderRequestDetail(id)`, `acceptRequest(id)`, `rejectRequest(id)`, `startRequest(id)`, `updateProgress(id, data)`, `completeRequest(id)`
- **UI Components**:
  1. Status header
  2. Client info card (name, phone, city)
  3. Request details (title, description, attachments)
  4. Status timeline
  5. Financial info
  6. Action buttons based on status:
     - New → Accept / Reject
     - Accepted → Start
     - In Progress → Update Progress / Complete
  7. Progress update form (note + optional attachment)

---

### 7.4 Messaging

#### `my_chats_screen.dart` (690 lines)
- **Purpose**: Chat threads list
- **API Calls**: `AccountModeService.isProviderMode`, `AuthService.getUserId()`, `MessagingService.fetchThreads(mode)`, `toggleFavorite`, `toggleBlock`, `toggleArchive`, `toggleUnread`, `reportThread`
- **UI**: Filter tabs (الكل/غير مقروءة/المفضلة/العملاء/الأحدث), search field, thread list cards (avatar, name, last message, time, unread badge)
- **Long-press menu**: Favorite/Unfavorite, Block/Unblock, Archive, Mark Unread, Report
- **Navigation**: Thread tap → `ChatDetailScreen`

#### `chat_detail_screen.dart` (1053 lines)
- **Purpose**: Full chat conversation view
- **API Calls**: `AuthService.getUserId()`, `MessagingService.getOrCreateDirectThread(peerId, peerProviderId, mode)`, `fetchMessages(threadId, limit, offset)`, `sendTextMessage(threadId, body)`, `sendAttachment(threadId, file, type)`, `markRead(threadId)`, `deleteMessage(threadId, messageId)`
- **UI Components**:
  1. Custom app bar with peer name + avatar
  2. Message bubbles (sent right purple, received left gray)
  3. Attachment types: audio player, image preview, file download link
  4. Text input field with attachment picker (camera, gallery, file, audio recording)
  5. Infinite scroll pagination (load older messages on scroll up)
  6. Auto-scroll to bottom on new message
  7. Message long-press → delete option
- **Audio**: In-chat audio recording via `flutter_sound`, playback with progress bar

---

### 7.5 Interactive / Social

#### `interactive_screen.dart` (793 lines)
- **Purpose**: Social engagement hub with 3 tabs
- **API Calls**: `AuthService.isLoggedIn()`, `AccountModeService.isProviderMode`, `InteractiveService.fetchFollowing(mode)`, `fetchFollowers()`, `fetchFavorites(mode)`, `fetchFavoriteSpotlights(mode)`, `unfollowProvider(id, mode)`, `unsavePortfolioItem(id, mode)`, `unsaveSpotlight(id, mode)`
- **Tab 1 — المتابَعون (Following)**: Grid of followed providers with unfollow option
- **Tab 2 — المتابِعون (Followers)**: Provider-only tab showing followers list
- **Tab 3 — المحفوظات (Favorites)**: Sub-tabs for portfolio items and spotlights, with unsave option
- **Login gate**: Shows login prompt if not authenticated

#### `provider_profile_screen.dart` (2634 lines — largest screen)
- **Purpose**: Public provider profile view (for both clients and other providers)
- **API Calls**: `InteractiveService.fetchProviderDetail(id)`, `fetchProviderStats(id)`, `fetchProviderServices(id)`, `fetchProviderPortfolio(id)`, `fetchProviderSpotlights(id)`, `fetchProviderFollowers(id, mode)`, `fetchProviderFollowing(id, mode)`, plus `followProvider`, `unfollowProvider`, `likeProvider`, `unlikeProvider`, `likePortfolio`, `unlikePortfolio`, `savePortfolio`, `likeSpotlight`, `unlikeSpotlight`, `saveSpotlight`
- **UI Components** (tab-based layout):
  1. **Header**: Cover image, profile image, display name, verification badges (blue/green), city, rating stars
  2. **Stats row**: Followers, Following, Likes, Completed Requests
  3. **Action buttons**: Follow/Unfollow, Like/Unlike, Chat, Request Service, WhatsApp, Share
  4. **Tab: الملف الشخصي (Profile)**: Bio, about, qualifications, experiences, languages, social links, map location
  5. **Tab: الخدمات (Services)**: List of provider's services with pricing
  6. **Tab: الأعمال (Portfolio)**: Media grid of portfolio items (images/videos) with like/save
  7. **Tab: التقييمات (Reviews)**: Reviews list with ratings
  8. **Spotlights section**: Horizontal scrollable spotlight previews → opens `SpotlightViewerPage`
- **Map**: Shows provider location with coverage radius circle

---

### 7.6 User Profile & Settings

#### `my_profile_screen.dart` (774 lines)
- **Purpose**: Current user's profile view and management
- **API Calls**: `AuthService.isLoggedIn()`, `ProfileService.fetchMyProfile()`, `ProfileService.uploadMyProfileImages(profileFile, coverFile)`, `AccountModeService.isProviderMode`, `AccountModeService.setProviderMode(bool)`
- **UI Components**:
  1. Cover image with edit overlay
  2. Profile image with edit overlay
  3. User info (name, username, phone)
  4. Stats: Following count, Likes, Favorites
  5. Mode toggle switch (Client ↔ Provider)
  6. Provider profile card (if has provider profile): display name, city, rating
  7. "سجل كمقدم خدمة" (Register as Provider) button if no provider profile
  8. Quick links: Orders, Chats, Notifications
- **Login gate**: Shows login prompt if not authenticated
- **Navigation**: Provider card → `ProviderHomeScreen`, Register → `RegisterServiceProvider`

#### `login_settings_screen.dart` (501 lines)
- **Purpose**: Edit account settings
- **API Calls**: `ProfileService.fetchMyProfile()`, `ProfileService.updateMyProfile(data)`
- **UI**: Editable fields: phone, email, first name, last name, username. Save button.

#### `notification_settings_screen.dart` (330 lines)
- **Purpose**: Toggle notification preferences
- **API Calls**: `NotificationService.fetchPreferences(mode)`, `NotificationService.updatePreferences(mode, data)`, `AccountModeService.apiMode`
- **UI**: List of notification types with toggle switches, grouped by category, locked indicators for tier-restricted preferences

---

### 7.7 Notifications

#### `notifications_screen.dart` (428 lines)
- **Purpose**: Full notifications list with management
- **API Calls**: `NotificationService.fetchNotifications(limit, offset, mode)`, `markRead(id)`, `markAllRead()`, `pinNotification(id)`, `followUpNotification(id)`, `removeAction(id)`, `deleteOld()`
- **UI**: Infinite-scroll list, notification cards with: title, body, time, read/unread style, pin/follow-up badges
- **Actions**: Long-press menu (mark read, pin, follow-up, remove), "Mark all read" in app bar, "Delete old" option
- **Deep linking**: Taps navigate based on `notification.url` field

---

### 7.8 Provider Dashboard

#### `provider_home_screen.dart` (1552 lines)
- **Purpose**: Provider's main dashboard
- **API Calls**: `ProfileService.fetchProviderProfile()`, `fetchMyProfile()`, `uploadProviderProfileImages()`, `uploadProviderSpotlight()`, `MarketplaceService.getAvailableUrgentRequests()`, `getProviderRequests(statusGroup)`, `SubscriptionsService.mySubscriptions()`, `InteractiveService.fetchMySpotlights()`, `deleteSpotlightItem(id)`, `AccountModeService.isProviderMode`
- **UI Components**:
  1. Profile header card (image, name, rating, edit buttons)
  2. Profile completion percentage bar
  3. Quick stats grid (orders, followers, rating)
  4. Urgent requests section (scrollable cards with accept button)
  5. Recent orders section (new + in-progress)
  6. Spotlights management (grid with add/delete)
  7. Subscription info card
  8. Quick action buttons (Edit Profile, My Services, Reviews, Promotions)
- **Navigation**: Various sections → respective detail screens

#### `profile_tab.dart` (609 lines)
- **Purpose**: Provider profile editing (tab within dashboard)
- **API Calls**: `ProfileService.fetchMyProfile()`, `fetchProviderProfile()`, `updateProviderProfile(data)`
- **UI**: Editable form: display name, bio, about, provider type, city, WhatsApp, website, social links, languages, qualifications, experiences

#### `services_tab.dart` (693 lines)
- **Purpose**: CRUD for provider's services
- **API Calls**: `ProviderServicesService.fetchCategories()`, `fetchMyServices()`, `createService(data)`, `updateService(id, data)`, `deleteService(id)`
- **UI**: Service list with edit/delete, "Add Service" FAB → dialog form (title, description, price, category, subcategory)

#### `reviews_tab.dart` (695 lines)
- **Purpose**: View and reply to reviews
- **API Calls**: `ProfileService.fetchMyProfile()`, `ReviewsService.fetchProviderReviews(providerId)`, `fetchProviderRating(providerId)`, `replyToReview(reviewId, body)`
- **UI**: Rating summary (average + breakdown), reviews list with: reviewer name, rating stars, comment, date, provider reply section

#### `promotion_screen.dart` (817 lines)
- **Purpose**: Create and manage promotional ad requests
- **API Calls**: `PromoService.createRequest(data)`, `fetchMyRequests()`, `uploadAsset(requestId, file)`
- **UI**: My promos list, create promo form (type, duration, budget), asset upload section (images/videos)

#### `provider_profile_completion_screen.dart` (768 lines)
- **Purpose**: Guide provider to complete their profile
- **API Calls**: `ProfileService.fetchProviderProfile()`, `fetchMyProfile()`, `ApiClient.get('/api/providers/me/services/')`
- **UI**: Section checklist (basic info, services, portfolio, about, contact, SEO) with completion % per section, tap each section to navigate to edit

---

### 7.9 Provider Registration Wizard

#### `register_service_provider.dart` (633 lines)
- **Purpose**: Multi-step provider registration flow
- **API Calls**: `ProfileService.fetchMyProfile()`, `registerProvider(data)`, `AccountModeService.setProviderMode(true)`
- **UI**: Stepper widget with 8 steps, progress bar, validation per step, final submit
- **Steps**: Personal Info → Service Classification → Service Details → Additional Details → Contact Info → Language & Location → Content → SEO

#### Step 1: `personal_info_step.dart` (206 lines)
- **Fields**: Display name, bio, provider type (فرد/شركة — Individual/Company)
- **API**: None (data passed via callback)

#### Step 2: `service_classification_step.dart` (997 lines)
- **Fields**: Category selection (multi-select grid), subcategory selection (multi-select within each category)
- **API**: `HomeService.fetchCategories()`
- **UI**: Category grid with icons, expandable subcategory lists

#### Step 3: `service_details_step.dart` (837 lines)
- **Fields**: Add/edit/delete individual services (title, description, price range)
- **API**: `ProfileService.fetchProviderProfile()`, `updateProviderProfile()`, `ProviderServicesService.fetchMyServices()`, `createService()`, `updateService()`, `deleteService()`, `ApiClient.get('/api/providers/me/subcategories/')`
- **UI**: Service cards list with inline edit, add new service dialog

#### Step 4: `additional_details_step.dart` (677 lines)
- **Fields**: Qualifications list, experiences list, about details text
- **API**: `ProfileService.fetchProviderProfile()`, `updateProviderProfile(data)`
- **UI**: Dynamic list builders with add/remove, text areas

#### Step 5: `contact_info_step.dart` (838 lines)
- **Fields**: WhatsApp number, website URL, social links (Instagram, Twitter/X, LinkedIn, YouTube, TikTok, Snapchat)
- **API**: `ProfileService.fetchProviderProfile()`, `updateProviderProfile(data)`
- **UI**: Input fields with URL validation, social platform icons

#### Step 6: `language_location_step.dart` (645 lines)
- **Fields**: Languages (multi-select), city dropdown, coverage radius (km), map pin
- **API**: `ProfileService.fetchProviderProfile()`, `updateProviderProfile(data)`
- **UI**: Language chips, city dropdown (SaudiCities), radius slider, `FlutterMap` with draggable pin + radius circle
- **Dependencies**: `flutter_map`, `latlong2`, `geolocator`

#### Step 7: `content_step.dart` (1250 lines)
- **Fields**: Profile image, cover image, portfolio items (images/videos), content sections (title + body)
- **API**: `ProfileService.fetchProviderProfile()`, `uploadProviderPortfolioItem(file, caption, fileType)`, `updateProviderProfile(data)`
- **UI**: Image pickers, portfolio upload grid, content section editor with add/remove
- **Media handling**: Image compression via `UploadOptimizer`, video upload

#### Step 8: `seo_step.dart` (232 lines)
- **Fields**: SEO keywords (comma-separated), meta description, URL slug
- **API**: `ProfileService.fetchProviderProfile()`, `updateProviderProfile(data)`
- **UI**: Text fields with character counters

#### `map_radius_picker_screen.dart` (277 lines)
- **Purpose**: Standalone map screen for picking location + coverage radius
- **API**: None (returns lat/lng/radius via Navigator.pop)
- **UI**: Full-screen map, radius slider, confirm button

---

### 7.10 Additional Screens

#### `about_screen.dart` (379 lines)
- **Purpose**: About Nawafeth with vision, goals, values
- **API Calls**: `ContentService.fetchPublicContent()`
- **UI**: Expandable section cards (Vision, Mission, Goals, Values), app version info, store links (Google Play, App Store)

#### `terms_screen.dart` (239 lines)
- **Purpose**: Terms & conditions display
- **API Calls**: `ContentService.fetchPublicContent()`
- **UI**: Scrollable rich text content from API, "Accept" button if shown during registration

#### `contact_screen.dart` (1138 lines)
- **Purpose**: Support center — create tickets, view list, ticket detail
- **API Calls**: `SupportService.fetchTeams()`, `createTicket(data)`, `fetchMyTickets(status, type)`, `fetchTicketDetail(id)`, `addComment(ticketId, body)`, `uploadAttachment(ticketId, file)`
- **UI Components**:
  1. **Tab 1 — Create Ticket**: Team selection, ticket type, title, description, priority dropdown, submit
  2. **Tab 2 — My Tickets**: Status filters (all/open/in_progress/resolved/closed), ticket cards list
  3. **Ticket Detail**: Status, description, attachments, reply thread, add comment input, upload attachment button

#### `plans_screen.dart` (276 lines)
- **Purpose**: View and subscribe to plans
- **API Calls**: `SubscriptionsService.getPlans()`, `SubscriptionsService.subscribe(planId)`
- **UI**: Plan cards with: name, price, features list, "Subscribe" button. Current plan highlighted.

#### `additional_services_screen.dart` (404 lines)
- **Purpose**: Browse and purchase extra services/add-ons
- **API Calls**: `ExtrasService.fetchCatalog()`, `ExtrasService.buy(sku)`
- **UI**: Catalog grid/list of extras with: name, description, price. Purchase confirmation dialog.

#### `verification_screen.dart` (1541 lines)
- **Purpose**: Identity verification wizard
- **API Calls**: `VerificationService.createRequest(data)`, `uploadDocument(requestId, file, docType)`
- **UI Components**:
  1. Verification type selection: Blue badge (personal identity/company), Green badge (other)
  2. Document upload sections (ID, commercial register, etc.)
  3. Status tracker for existing requests
  4. Payment integration for verification fee

#### `service_detail_screen.dart` (874 lines)
- **Purpose**: View a single service's details
- **API Calls**: None (receives data via constructor)
- **UI**: Image slider/gallery, service title, description, price, provider info card, comments/reviews section, like/share actions

#### `upgrade_screen.dart` (11 lines) — Placeholder
#### `verification_screen.dart` in provider_dashboard (11 lines) — Placeholder

---

## 8. Widgets — Reusable Components

### 8.1 `app_bar.dart` (379 lines) — Custom AppBar

- **Features**: Menu hamburger / back button, optional search field with real-time input, notification bell with unread badge, chat icon with unread badge
- **Navigation**: Menu → opens drawer, Notifications → `NotificationsScreen`, Chat → `MyChatsScreen`
- **Props**: `showSearch`, `onSearchChanged`, `title`, `showBack`

### 8.2 `bottom_nav.dart` (278 lines) — Bottom Navigation

- **Tabs**: Home, Orders, (+) FAB, Interactive, Profile
- **Mode-aware**: In provider mode, orders label changes from "طلباتي" to "طلبات الخدمة"
- **FAB**: Center floating purple button for "Add Service"
- **State**: `currentIndex` managed by parent

### 8.3 `custom_drawer.dart` (594 lines) — Side Drawer

- **API Calls**: `AuthService` (check login), `ProfileService.fetchMyProfile()`, `ApiClient.post('/api/accounts/logout/')`, `ApiClient.delete('/api/accounts/delete/')`
- **Sections**:
  1. User header (avatar, name, phone)
  2. Navigation links (Home, Settings, Language, QR Code, Terms, Support, About)
  3. Theme toggle (light/dark)
  4. Logout button (with confirmation dialog)
  5. Delete account button (with confirmation dialog)

### 8.4 `banner_widget.dart` — Video Banner Player

- Plays `assets/videos/V16.mp4` as hero background
- Auto-play, muted, looping
- Gradient overlay for text readability

### 8.5 `auto_scrolling_reels_row.dart` (133 lines) — Spotlight Reels Row

- Infinite auto-scrolling horizontal list of spotlight thumbnails
- Circular profile images with purple gradient border
- Tap → opens `SpotlightViewerPage`
- Timer-based smooth scroll animation

### 8.6 `profiles_slider.dart` (141 lines) — Provider Profile Circles

- Auto-scrolling horizontal row of provider profile circles
- Tap → navigates to provider profile
- Infinite scroll via list duplication

### 8.7 `spotlight_viewer.dart` (580 lines) — TikTok-style Spotlight Viewer

- **Purpose**: Full-screen vertical swipe spotlight/story viewer
- **API Calls**: `InteractiveService.likeSpotlight()`, `unlikeSpotlight()`, `saveSpotlight()`, `unsaveSpotlight()`
- **UI**: Full-screen media (image/video), vertical PageView swipe, side action bar (like, save, share, profile), provider info overlay
- **Video**: VideoPlayerController with auto-play, looping, error handling
- **Optimistic updates**: Like/save counts update immediately, revert on API failure

### 8.8 `video_reels.dart` (224 lines) — Video Reel Thumbnails

- Auto-scrolling horizontal list of video thumbnails with logos
- Tap → opens `VideoFullScreenPage`
- Infinite scroll via list duplication

### 8.9 `video_full_screen.dart` (839 lines) — Full-Screen Video Player

- **Purpose**: Full-screen video viewer with swipe navigation
- **UI**: PageView for horizontal swipe between videos, play/pause tap, like/save buttons, progress bar, user avatars
- **Features**: Swipe hint animation, bubble animation for like/save feedback
- **Controls**: Tap to play/pause, double-tap to like, volume control

### 8.10 `provider_media_grid.dart` (106 lines) — Provider Media Grid

- Static grid of media thumbnails (images) with expand/collapse
- "عرض المزيد" (Show More) / "عرض أقل" (Show Less) toggle

### 8.11 `service_grid.dart` (129 lines) — Service Cards Grid

- Static grid of service type cards with icons
- 12 pre-defined service categories (legal, engineering, design, delivery, etc.)
- Expand/collapse functionality

### 8.12 `testimonials_slider.dart` (153 lines) — Testimonials Carousel

- Auto-scrolling PageView of testimonial cards
- Static data (3 testimonials with name, comment, rating)
- Rating stars display

### 8.13 `platform_report_dialog.dart` (269 lines) — Report Dialog

- **Purpose**: Reusable report/flag dialog for any entity
- **UI**: Reason dropdown (6 predefined Arabic reasons: inappropriate content, harassment, fraud, abuse, privacy violation, other), details text field, submit button
- **Callback**: `PlatformReportSubmit({ reason, details })`

---

## 9. Dual-Mode Architecture

The app supports two user modes:

| Aspect | Client Mode | Provider Mode |
|--------|-------------|---------------|
| **Toggle** | Default for all users | Requires provider profile registration |
| **Storage** | `SharedPreferences` key `isProvider = false` | `isProvider = true` |
| **API Param** | `?mode=client` | `?mode=provider` |
| **Route Access** | All routes | Blocked from: `/add_service`, `/search_provider`, `/urgent_request`, `/request_quote` |
| **Orders View** | `ClientOrdersScreen` | `ProviderOrdersScreen` |
| **Bottom Nav Label** | "طلباتي" (My Orders) | "طلبات الخدمة" (Service Orders) |
| **Interactive Tab** | Following + Favorites | Following + Followers + Favorites |
| **Home Screen** | Standard home | Provider Dashboard (`ProviderHomeScreen`) via profile |
| **Profile** | User profile | User profile + Provider profile card |

**Mode-affected API endpoints** (pass `?mode=client|provider`):
- Messaging: threads, send
- Notifications: all endpoints
- Interactive: following, favorites, like, save, follow, unfollow
- Marketplace: different endpoint sets for client vs provider

---

## 10. Theme & Styling

| Property | Value |
|----------|-------|
| **Font** | Cairo (Google Fonts) |
| **Direction** | RTL (Arabic) |
| **Primary Color** | Deep Purple `#663D90` |
| **Accent** | Orange `#FF9800` |
| **Background** | White `#FFFFFF` |
| **Card Style** | Rounded corners (12-16px), subtle shadow, thin border |
| **Light/Dark** | Both supported via `MyThemeController` InheritedWidget |
| **Locale** | `ar_SA` default, English supported via `app_texts.dart` |
| **Status Bar** | Light icons on dark background in several screens |

### Common UI Patterns (for web rebuild reference)

1. **Card pattern**: White bg, `borderRadius: 14`, `boxShadow: black12 blur:6 offset(0,2)`, thin purple border
2. **Buttons**: Deep purple filled, white text, Cairo font, rounded 12px
3. **Empty states**: Icon + text + action button
4. **Loading**: `CircularProgressIndicator(color: deepPurple)`
5. **Pull-to-refresh**: `RefreshIndicator` wrapping scroll views
6. **Infinite scroll**: `ScrollController` with `offset > max - 200` trigger
7. **Form validation**: Inline error messages below fields, Arabic text
8. **Dialogs**: `AlertDialog` with RTL directionality, rounded 20px
9. **Snackbars**: Bottom positioned, Cairo font, rounded corners
10. **Tabs**: `TabBar` with deep purple indicator, Cairo font labels

---

## Complete API Endpoint Summary (Deduplicated)

### Accounts
```
POST   /api/accounts/otp/send/
POST   /api/accounts/otp/verify/
GET    /api/accounts/username-availability/?username=
POST   /api/accounts/complete/
POST   /api/accounts/token/refresh/
GET    /api/accounts/me/
PATCH  /api/accounts/me/
POST   /api/accounts/logout/
DELETE /api/accounts/delete/
GET    /api/accounts/wallet/
```

### Providers
```
GET    /api/providers/categories/
GET    /api/providers/list/?search=&category=&lat=&lng=&radius=&page_size=
GET    /api/providers/{id}/
GET    /api/providers/{id}/services/
GET    /api/providers/{id}/stats/
GET    /api/providers/{id}/portfolio/
GET    /api/providers/{id}/spotlights/
GET    /api/providers/{id}/followers/?mode=
GET    /api/providers/{id}/following/?mode=
POST   /api/providers/{id}/follow/?mode=
POST   /api/providers/{id}/unfollow/?mode=
POST   /api/providers/{id}/like/?mode=
POST   /api/providers/{id}/unlike/?mode=
POST   /api/providers/register/
GET    /api/providers/me/profile/
PATCH  /api/providers/me/profile/
GET    /api/providers/me/services/
POST   /api/providers/me/services/
PATCH  /api/providers/me/services/{id}/
DELETE /api/providers/me/services/{id}/
GET    /api/providers/me/subcategories/
GET    /api/providers/me/portfolio/
POST   /api/providers/me/portfolio/
DELETE /api/providers/me/portfolio/{id}/
GET    /api/providers/me/spotlights/
POST   /api/providers/me/spotlights/
DELETE /api/providers/me/spotlights/{id}/
GET    /api/providers/me/following/?mode=
GET    /api/providers/me/followers/
GET    /api/providers/me/favorites/?mode=
GET    /api/providers/me/favorites/spotlights/?mode=
POST   /api/providers/portfolio/{id}/like/?mode=
POST   /api/providers/portfolio/{id}/unlike/?mode=
POST   /api/providers/portfolio/{id}/save/?mode=
POST   /api/providers/portfolio/{id}/unsave/?mode=
POST   /api/providers/spotlights/{id}/like/?mode=
POST   /api/providers/spotlights/{id}/unlike/?mode=
POST   /api/providers/spotlights/{id}/save/?mode=
POST   /api/providers/spotlights/{id}/unsave/?mode=
GET    /api/providers/spotlights/feed/?limit=
```

### Marketplace
```
POST   /api/marketplace/requests/create/
GET    /api/marketplace/client/requests/?status_group=&type=&q=
GET    /api/marketplace/client/requests/{id}/
PATCH  /api/marketplace/client/requests/{id}/
POST   /api/marketplace/requests/{id}/cancel/
POST   /api/marketplace/requests/{id}/reopen/
POST   /api/marketplace/requests/{id}/start/
POST   /api/marketplace/requests/{id}/complete/
GET    /api/marketplace/requests/{id}/offers/
POST   /api/marketplace/requests/{id}/offers/create/
POST   /api/marketplace/offers/{id}/accept/
GET    /api/marketplace/provider/requests/?status_group=&client_user_id=
GET    /api/marketplace/provider/requests/{id}/detail/
POST   /api/marketplace/provider/requests/{id}/accept/
POST   /api/marketplace/provider/requests/{id}/reject/
POST   /api/marketplace/provider/requests/{id}/progress-update/
GET    /api/marketplace/provider/urgent/available/
POST   /api/marketplace/requests/urgent/accept/
GET    /api/marketplace/provider/competitive/available/
```

### Messaging
```
GET    /api/messaging/direct/threads/?mode=
GET    /api/messaging/threads/states/?mode=
POST   /api/messaging/direct/thread/
GET    /api/messaging/direct/thread/{id}/messages/?limit=&offset=
POST   /api/messaging/direct/thread/{id}/messages/send/
POST   /api/messaging/direct/thread/{id}/messages/read/
POST   /api/messaging/thread/{id}/unread/
POST   /api/messaging/thread/{id}/favorite/
POST   /api/messaging/thread/{id}/block/
POST   /api/messaging/thread/{id}/archive/
POST   /api/messaging/thread/{id}/report/
POST   /api/messaging/thread/{id}/messages/{mid}/delete/
```

### Notifications
```
GET    /api/notifications/?limit=&offset=&mode=
GET    /api/notifications/unread-count/?mode=
POST   /api/notifications/mark-read/{id}/?mode=
POST   /api/notifications/mark-all-read/?mode=
POST   /api/notifications/actions/{id}/?mode=
DELETE /api/notifications/actions/{id}/?mode=
GET    /api/notifications/preferences/?mode=
PATCH  /api/notifications/preferences/?mode=
POST   /api/notifications/device-token/
POST   /api/notifications/delete-old/?mode=
```

### Billing
```
GET    /api/billing/invoices/my/
GET    /api/billing/invoices/{id}/
POST   /api/billing/invoices/{id}/init-payment/
```

### Subscriptions
```
GET    /api/subscriptions/plans/
GET    /api/subscriptions/my/
POST   /api/subscriptions/subscribe/{planId}/
```

### Reviews
```
POST   /api/reviews/requests/{id}/review/
GET    /api/reviews/providers/{id}/reviews/
GET    /api/reviews/providers/{id}/rating/
POST   /api/reviews/reviews/{id}/provider-reply/
```

### Support
```
GET    /api/support/teams/
POST   /api/support/tickets/create/
GET    /api/support/tickets/my/?status=&type=
GET    /api/support/tickets/{id}/
POST   /api/support/tickets/{id}/comments/
POST   /api/support/tickets/{id}/attachments/
```

### Verification
```
POST   /api/verification/requests/create/
GET    /api/verification/requests/my/
GET    /api/verification/requests/{id}/
POST   /api/verification/requests/{id}/documents/
```

### Promo
```
POST   /api/promo/requests/create/
GET    /api/promo/requests/my/
GET    /api/promo/requests/{id}/
POST   /api/promo/requests/{id}/assets/
GET    /api/promo/banners/home/?limit=
```

### Extras
```
GET    /api/extras/catalog/
GET    /api/extras/my/
POST   /api/extras/buy/{sku}/
```

### Features
```
GET    /api/features/my/
```

### Content
```
GET    /api/content/public/
```

---

**Total: ~100 unique API endpoints across 13 backend modules**

**Total: 40+ screens, 13 widgets, 18+ services, 14+ models**
