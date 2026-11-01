#ifndef RUNNER_MEDIA_SESSION_HOST_H_
#define RUNNER_MEDIA_SESSION_HOST_H_

#include <flutter/binary_messenger.h>

#include <memory>

// Exposes the Windows GSMTC media session over the platform media channel.
class MediaSessionHost {
 public:
  explicit MediaSessionHost(flutter::BinaryMessenger* messenger);
  ~MediaSessionHost();

  MediaSessionHost(const MediaSessionHost&) = delete;
  MediaSessionHost& operator=(const MediaSessionHost&) = delete;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_SESSION_HOST_H_
