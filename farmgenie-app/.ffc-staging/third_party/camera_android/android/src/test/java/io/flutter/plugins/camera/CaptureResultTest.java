package io.flutter.plugins.camera;

import static org.mockito.Mockito.*;
import org.junit.Test;

public class CaptureResultTest {
  @Test
  public void savedPhotoThenLateCameraErrorRepliesOnlyOnce() {
    Messages.Result<String> delegate = mock(Messages.Result.class);
    CaptureResult result = new CaptureResult(delegate);
    result.success("selfie.jpg");
    result.error(new IllegalStateException("Camera is closed"));
    result.success("selfie.jpg");
    verify(delegate).success("selfie.jpg");
    verifyNoMoreInteractions(delegate);
  }

  @Test
  public void failedCaptureThenLateImageDoesNotReplyAgain() {
    Messages.Result<String> delegate = mock(Messages.Result.class);
    CaptureResult result = new CaptureResult(delegate);
    Throwable error = new IllegalStateException("Capture failed");
    result.error(error);
    result.success("late.jpg");
    result.error(error);
    verify(delegate).error(error);
    verifyNoMoreInteractions(delegate);
  }
}
