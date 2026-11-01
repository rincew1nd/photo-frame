#include "media_session_host.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.System.h>
#include <winrt/base.h>

#include <memory>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionManager;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionPlaybackStatus;
using winrt::Windows::System::DispatcherQueue;

EncodableMap EmptyState() {
  return EncodableMap{
      {EncodableValue("hasSession"), EncodableValue(false)},
      {EncodableValue("title"), EncodableValue()},
      {EncodableValue("artist"), EncodableValue()},
      {EncodableValue("album"), EncodableValue()},
      {EncodableValue("packageName"), EncodableValue()},
      {EncodableValue("playing"), EncodableValue(false)},
      {EncodableValue("canPrevious"), EncodableValue(false)},
      {EncodableValue("canNext"), EncodableValue(false)},
      {EncodableValue("positionSeconds"), EncodableValue()},
      {EncodableValue("durationSeconds"), EncodableValue()},
  };
}

void SetString(EncodableMap& state, const char* key, const winrt::hstring& value) {
  if (value.empty()) {
    state[EncodableValue(key)] = EncodableValue();
    return;
  }
  state[EncodableValue(key)] = EncodableValue(winrt::to_string(value));
}

winrt::fire_and_forget GetMediaStateAsync(DispatcherQueue dispatcher,
                                          std::unique_ptr<MethodResult<EncodableValue>>
                                              result) {
  EncodableMap state = EmptyState();
  try {
    auto manager =
        co_await GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
    if (manager) {
      auto session = manager.GetCurrentSession();
      if (session) {
        state[EncodableValue("hasSession")] = EncodableValue(true);
        SetString(state, "packageName", session.SourceAppUserModelId());

        auto properties = co_await session.TryGetMediaPropertiesAsync();
        if (properties) {
          SetString(state, "title", properties.Title());
          SetString(state, "artist", properties.Artist());
          SetString(state, "album", properties.AlbumTitle());
        }

        auto playback = session.GetPlaybackInfo();
        if (playback) {
          state[EncodableValue("playing")] = EncodableValue(
              playback.PlaybackStatus() ==
              GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing);
          auto controls = playback.Controls();
          if (controls) {
            state[EncodableValue("canPrevious")] =
                EncodableValue(controls.IsPreviousEnabled());
            state[EncodableValue("canNext")] =
                EncodableValue(controls.IsNextEnabled());
          }
        }

        auto timeline = session.GetTimelineProperties();
        if (timeline) {
          const double position =
              static_cast<double>(timeline.Position().count()) / 10000000.0;
          const double duration =
              static_cast<double>(timeline.EndTime().count()) / 10000000.0;
          state[EncodableValue("positionSeconds")] = EncodableValue(position);
          if (duration > 0.0) {
            state[EncodableValue("durationSeconds")] = EncodableValue(duration);
          }
        }
      }
    }
  } catch (...) {
    state = EmptyState();
  }

  if (dispatcher) {
    try {
      co_await winrt::resume_foreground(dispatcher);
    } catch (...) {
    }
  }
  result->Success(EncodableValue(state));
}

winrt::fire_and_forget ControlAsync(DispatcherQueue dispatcher,
                                    std::unique_ptr<MethodResult<EncodableValue>>
                                        result,
                                    std::string action) {
  bool handled = false;
  try {
    auto manager =
        co_await GlobalSystemMediaTransportControlsSessionManager::RequestAsync();
    if (manager) {
      auto session = manager.GetCurrentSession();
      if (session) {
        if (action == "previous") {
          handled = co_await session.TrySkipPreviousAsync();
        } else if (action == "next") {
          handled = co_await session.TrySkipNextAsync();
        } else if (action == "toggle") {
          handled = co_await session.TryTogglePlayPauseAsync();
        }
      }
    }
  } catch (...) {
    handled = false;
  }

  if (dispatcher) {
    try {
      co_await winrt::resume_foreground(dispatcher);
    } catch (...) {
    }
  }
  result->Success(EncodableValue(handled));
}

}  // namespace

class MediaSessionHost::Impl {
 public:
  explicit Impl(flutter::BinaryMessenger* messenger) {
    dispatcher_ = DispatcherQueue::GetForCurrentThread();
    channel_ =
        std::make_unique<flutter::MethodChannel<EncodableValue>>(
            messenger, "com.rincew1nd.photoframe/media",
            &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler(
        [](const MethodCall<EncodableValue>& call,
           std::unique_ptr<MethodResult<EncodableValue>> result) {
          const auto dispatcher = DispatcherQueue::GetForCurrentThread();
          if (call.method_name() == "getMediaState") {
            GetMediaStateAsync(dispatcher, std::move(result));
            return;
          }
          if (call.method_name() == "mediaControl") {
            const auto* arguments =
                std::get_if<flutter::EncodableMap>(call.arguments());
            std::string action;
            if (arguments != nullptr) {
              const auto action_it = arguments->find(EncodableValue("action"));
              if (action_it != arguments->end()) {
                if (const auto* value =
                        std::get_if<std::string>(&action_it->second)) {
                  action = *value;
                }
              }
            }
            ControlAsync(dispatcher, std::move(result), action);
            return;
          }
          if (call.method_name() == "hasNotificationAccess") {
            result->Success(EncodableValue(true));
            return;
          }
          if (call.method_name() == "openNotificationAccessSettings") {
            result->Success(EncodableValue(true));
            return;
          }
          result->NotImplemented();
        });
  }

  ~Impl() {
    if (channel_) {
      channel_->SetMethodCallHandler(nullptr);
      channel_.reset();
    }
  }

 private:
  DispatcherQueue dispatcher_{nullptr};
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel_;
};

MediaSessionHost::MediaSessionHost(flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

MediaSessionHost::~MediaSessionHost() = default;
