package io.flutter.plugins.camera;

import androidx.annotation.NonNull;
import java.util.concurrent.atomic.AtomicBoolean;

/** A photo request can receive competing Camera2 and image-save callbacks. */
final class CaptureResult implements Messages.Result<String> {
  private final Messages.Result<String> delegate;
  private final AtomicBoolean completed = new AtomicBoolean();

  CaptureResult(Messages.Result<String> delegate) {
    this.delegate = delegate;
  }

  @Override
  public void success(@NonNull String path) {
    if (completed.compareAndSet(false, true)) delegate.success(path);
  }

  @Override
  public void error(@NonNull Throwable error) {
    if (completed.compareAndSet(false, true)) delegate.error(error);
  }
}
