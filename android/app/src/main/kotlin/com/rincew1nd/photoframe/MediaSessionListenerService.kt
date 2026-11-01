package com.rincew1nd.photoframe

import android.service.notification.NotificationListenerService

/**
 * Enables notification access for MediaSessionManager.getActiveSessions().
 * The service itself does not read notifications.
 */
class MediaSessionListenerService : NotificationListenerService()
