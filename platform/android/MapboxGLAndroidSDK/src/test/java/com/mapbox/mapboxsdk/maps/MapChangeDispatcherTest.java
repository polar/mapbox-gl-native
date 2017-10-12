package com.mapbox.mapboxsdk.maps;

import org.junit.Before;
import org.junit.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * Tests integration of MapChangeDispatcher and see if events are correctly forwarded.
 */
public class MapChangeDispatcherTest {

  private static final String TEST_STRING = "mapChangeRandom";

  private MapChangeDispatcher mapChangeDispatcher;

  @Mock
  private MapView.OnCameraWillChangeListener onCameraWillChangeListener;

  @Mock
  private MapView.OnCameraDidChangeListener onCameraDidChangeListener;

  @Mock
  private MapView.OnCameraIsChangingListener onCameraIsChangingListener;

  @Mock
  private MapView.OnWillStartLoadingMapListener onWillStartLoadingMapListener;

  @Mock
  private MapView.OnDidFinishLoadingMapListener onDidFinishLoadingMapListener;

  @Mock
  private MapView.OnDidFailLoadingMapListener onDidFailLoadingMapListener;

  @Mock
  private MapView.OnWillStartRenderingFrameListener onWillStartRenderingFrameListener;

  @Mock
  private MapView.OnDidFinishRenderingFrameListener onDidFinishRenderingFrameListener;

  @Mock
  private MapView.OnWillStartRenderingMapListener onWillStartRenderingMapListener;

  @Mock
  private MapView.OnDidFinishRenderingMapListener onDidFinishRenderingMapListener;

  @Mock
  private MapView.OnDidFinishLoadingStyleListener onDidFinishLoadingStyleListener;

  @Mock
  private MapView.OnSourceChangedListener onSourceChangedListener;

  @Mock
  private MapView.OnMapChangedListener onMapChangedListener;

  @Mock
  private MapView.MapChangeInternalHandler mapCallback;

  @Before
  public void beforeTest() {
    MockitoAnnotations.initMocks(this);
    mapChangeDispatcher = new MapChangeDispatcher();
    mapChangeDispatcher.addOnMapChangedListener(onMapChangedListener);
    mapChangeDispatcher.bind(mapCallback);
  }

  @Test
  public void testOnCameraRegionWillChangeListener() throws Exception {
    mapChangeDispatcher.addOnCameraWillChangeListener(onCameraWillChangeListener);
    mapChangeDispatcher.onCameraWillChange(false);
    verify(onCameraWillChangeListener).onCameraWillChange(false);
    verify(onMapChangedListener).onMapChanged(MapView.REGION_WILL_CHANGE);
    mapChangeDispatcher.removeOnCameraWillChangeListener(onCameraWillChangeListener);
    mapChangeDispatcher.onCameraWillChange(false);
    verify(onCameraWillChangeListener).onCameraWillChange(false);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.REGION_WILL_CHANGE);
  }

  @Test
  public void testOnCameraRegionWillChangeAnimatedListener() throws Exception {
    mapChangeDispatcher.addOnCameraWillChangeListener(onCameraWillChangeListener);
    mapChangeDispatcher.onCameraWillChange(true);
    verify(onCameraWillChangeListener).onCameraWillChange(true);
    verify(onMapChangedListener).onMapChanged(MapView.REGION_WILL_CHANGE_ANIMATED);
    mapChangeDispatcher.removeOnCameraWillChangeListener(onCameraWillChangeListener);
    mapChangeDispatcher.onCameraWillChange(true);
    verify(onCameraWillChangeListener).onCameraWillChange(true);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.REGION_WILL_CHANGE_ANIMATED);
  }

  @Test
  public void testOnCameraIsChangingListener() throws Exception {
    mapChangeDispatcher.addOnCameraIsChangingListener(onCameraIsChangingListener);
    mapChangeDispatcher.onCameraIsChanging();
    verify(onCameraIsChangingListener).onCameraIsChanging();
    verify(onMapChangedListener).onMapChanged(MapView.REGION_IS_CHANGING);
    verify(mapCallback).onCameraIsChanging();
    mapChangeDispatcher.removeOnCameraIsChangingListener(onCameraIsChangingListener);
    mapChangeDispatcher.onCameraIsChanging();
    verify(onCameraIsChangingListener).onCameraIsChanging();
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.REGION_IS_CHANGING);
  }

  @Test
  public void testOnCameraRegionDidChangeListener() throws Exception {
    mapChangeDispatcher.addOnCameraDidChangeListener(onCameraDidChangeListener);
    mapChangeDispatcher.onCameraDidChange(false);
    verify(onCameraDidChangeListener).onCameraDidChange(false);
    verify(onMapChangedListener).onMapChanged(MapView.REGION_DID_CHANGE);
    verify(mapCallback).onCameraDidChange(false);
    mapChangeDispatcher.removeOnCameraDidChangeListener(onCameraDidChangeListener);
    mapChangeDispatcher.onCameraDidChange(false);
    verify(onCameraDidChangeListener).onCameraDidChange(false);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.REGION_DID_CHANGE);
  }

  @Test
  public void testOnCameraRegionDidChangeAnimatedListener() throws Exception {
    mapChangeDispatcher.addOnCameraDidChangeListener(onCameraDidChangeListener);
    mapChangeDispatcher.onCameraDidChange(true);
    verify(onCameraDidChangeListener).onCameraDidChange(true);
    verify(onMapChangedListener).onMapChanged(MapView.REGION_DID_CHANGE_ANIMATED);
    verify(mapCallback).onCameraDidChange(true);
    mapChangeDispatcher.removeOnCameraDidChangeListener(onCameraDidChangeListener);
    mapChangeDispatcher.onCameraDidChange(true);
    verify(onCameraDidChangeListener).onCameraDidChange(true);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.REGION_DID_CHANGE_ANIMATED);
    verify(mapCallback, times(2)).onCameraDidChange(true);
  }

  @Test
  public void testOnWillStartLoadingMapListener() throws Exception {
    mapChangeDispatcher.addOnWillStartLoadingMapListener(onWillStartLoadingMapListener);
    mapChangeDispatcher.onWillStartLoadingMap();
    verify(onWillStartLoadingMapListener).onWillStartLoadingMap();
    verify(onMapChangedListener).onMapChanged(MapView.WILL_START_LOADING_MAP);
    mapChangeDispatcher.removeOnWillStartLoadingMapListener(onWillStartLoadingMapListener);
    mapChangeDispatcher.onWillStartLoadingMap();
    verify(onWillStartLoadingMapListener).onWillStartLoadingMap();
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.WILL_START_LOADING_MAP);
  }

  @Test
  public void testOnDidFinishLoadingMapListener() throws Exception {
    mapChangeDispatcher.addOnDidFinishLoadingMapListener(onDidFinishLoadingMapListener);
    mapChangeDispatcher.onDidFinishLoadingMap();
    verify(onDidFinishLoadingMapListener).onDidFinishLoadingMap();
    verify(onMapChangedListener).onMapChanged(MapView.DID_FINISH_LOADING_MAP);
    verify(mapCallback).onDidFinishLoadingMap();
    mapChangeDispatcher.removeOnDidFinishLoadingMapListener(onDidFinishLoadingMapListener);
    mapChangeDispatcher.onDidFinishLoadingMap();
    verify(onDidFinishLoadingMapListener).onDidFinishLoadingMap();
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FINISH_LOADING_MAP);
    verify(mapCallback, times(2)).onDidFinishLoadingMap();
  }

  @Test
  public void testOnDidFailLoadingMapListener() throws Exception {
    mapChangeDispatcher.addOnDidFailLoadingMapListener(onDidFailLoadingMapListener);
    mapChangeDispatcher.onDidFailLoadingMap(TEST_STRING);
    verify(onDidFailLoadingMapListener).onDidFailLoadingMap(TEST_STRING);
    verify(onMapChangedListener).onMapChanged(MapView.DID_FAIL_LOADING_MAP);
    mapChangeDispatcher.removeOnDidFailLoadingMapListener(onDidFailLoadingMapListener);
    mapChangeDispatcher.onDidFailLoadingMap(TEST_STRING);
    verify(onDidFailLoadingMapListener).onDidFailLoadingMap(TEST_STRING);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FAIL_LOADING_MAP);
  }

  @Test
  public void testOnWillStartRenderingFrameListener() throws Exception {
    mapChangeDispatcher.addOnWillStartRenderingFrameListener(onWillStartRenderingFrameListener);
    mapChangeDispatcher.onWillStartRenderingFrame();
    verify(onWillStartRenderingFrameListener).onWillStartRenderingFrame();
    verify(onMapChangedListener).onMapChanged(MapView.WILL_START_RENDERING_FRAME);
    mapChangeDispatcher.removeOnWillStartRenderingFrameListener(onWillStartRenderingFrameListener);
    mapChangeDispatcher.onWillStartRenderingFrame();
    verify(onWillStartRenderingFrameListener).onWillStartRenderingFrame();
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.WILL_START_RENDERING_FRAME);
  }

  @Test
  public void testOnDidFinishRenderingFrameListener() throws Exception {
    mapChangeDispatcher.addOnDidFinishRenderingFrameListener(onDidFinishRenderingFrameListener);
    mapChangeDispatcher.onDidFinishRenderingFrame(true);
    verify(onDidFinishRenderingFrameListener).onDidFinishRenderingFrame(true);
    verify(onMapChangedListener).onMapChanged(MapView.DID_FINISH_RENDERING_FRAME);
    verify(mapCallback).onDidFinishRenderingFrame(true);
    mapChangeDispatcher.removeOnDidFinishRenderingFrameListener(onDidFinishRenderingFrameListener);
    mapChangeDispatcher.onDidFinishRenderingFrame(true);
    verify(onDidFinishRenderingFrameListener).onDidFinishRenderingFrame(true);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FINISH_RENDERING_FRAME);
    verify(mapCallback, times(2)).onDidFinishRenderingFrame(true);
  }

  @Test
  public void testOnDidFinishRenderingFrameFullyRenderedListener() throws Exception {
    mapChangeDispatcher.addOnDidFinishRenderingFrameListener(onDidFinishRenderingFrameListener);
    mapChangeDispatcher.onDidFinishRenderingFrame(false);
    verify(onDidFinishRenderingFrameListener).onDidFinishRenderingFrame(false);
    verify(onMapChangedListener).onMapChanged(MapView.DID_FINISH_RENDERING_FRAME_FULLY_RENDERED);
    verify(mapCallback).onDidFinishRenderingFrame(false);
    mapChangeDispatcher.removeOnDidFinishRenderingFrameListener(onDidFinishRenderingFrameListener);
    mapChangeDispatcher.onDidFinishRenderingFrame(false);
    verify(onDidFinishRenderingFrameListener).onDidFinishRenderingFrame(false);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FINISH_RENDERING_FRAME_FULLY_RENDERED);
    verify(mapCallback, times(2)).onDidFinishRenderingFrame(false);
  }

  @Test
  public void testOnWillStartRenderingMapListener() throws Exception {
    mapChangeDispatcher.addOnWillStartRenderingMapListener(onWillStartRenderingMapListener);
    mapChangeDispatcher.onWillStartRenderingMap();
    verify(onWillStartRenderingMapListener).onWillStartRenderingMap();
    verify(onMapChangedListener).onMapChanged(MapView.WILL_START_RENDERING_MAP);
    mapChangeDispatcher.removeOnWillStartRenderingMapListener(onWillStartRenderingMapListener);
    mapChangeDispatcher.onWillStartRenderingMap();
    verify(onWillStartRenderingMapListener).onWillStartRenderingMap();
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.WILL_START_RENDERING_MAP);
  }

  @Test
  public void testOnDidFinishRenderingMapListener() throws Exception {
    mapChangeDispatcher.addOnDidFinishRenderingMapListener(onDidFinishRenderingMapListener);
    mapChangeDispatcher.onDidFinishRenderingMap(true);
    verify(onDidFinishRenderingMapListener).onDidFinishRenderingMap(true);
    verify(onMapChangedListener).onMapChanged(MapView.DID_FINISH_RENDERING_MAP);
    mapChangeDispatcher.removeOnDidFinishRenderingMapListener(onDidFinishRenderingMapListener);
    mapChangeDispatcher.onDidFinishRenderingMap(true);
    verify(onDidFinishRenderingMapListener).onDidFinishRenderingMap(true);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FINISH_RENDERING_MAP);
  }

  @Test
  public void testOnDidFinishRenderingMapFullyRenderedListener() throws Exception {
    mapChangeDispatcher.addOnDidFinishRenderingMapListener(onDidFinishRenderingMapListener);
    mapChangeDispatcher.onDidFinishRenderingMap(false);
    verify(onDidFinishRenderingMapListener).onDidFinishRenderingMap(false);
    verify(onMapChangedListener).onMapChanged(MapView.DID_FINISH_RENDERING_MAP_FULLY_RENDERED);
    mapChangeDispatcher.removeOnDidFinishRenderingMapListener(onDidFinishRenderingMapListener);
    mapChangeDispatcher.onDidFinishRenderingMap(false);
    verify(onDidFinishRenderingMapListener).onDidFinishRenderingMap(false);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FINISH_RENDERING_MAP_FULLY_RENDERED);
  }

  @Test
  public void testOnDidFinishLoadingStyleListener() throws Exception {
    mapChangeDispatcher.addOnDidFinishLoadingStyleListener(onDidFinishLoadingStyleListener);
    mapChangeDispatcher.onDidFinishLoadingStyle();
    verify(onDidFinishLoadingStyleListener).onDidFinishLoadingStyle();
    verify(onMapChangedListener).onMapChanged(MapView.DID_FINISH_LOADING_STYLE);
    verify(mapCallback).onDidFinishLoadingStyle();
    mapChangeDispatcher.removeOnDidFinishLoadingStyleListener(onDidFinishLoadingStyleListener);
    mapChangeDispatcher.onDidFinishLoadingStyle();
    verify(onDidFinishLoadingStyleListener).onDidFinishLoadingStyle();
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.DID_FINISH_LOADING_STYLE);
    verify(mapCallback, times(2)).onDidFinishLoadingStyle();
  }

  @Test
  public void testOnSourceChangedListener() throws Exception {
    mapChangeDispatcher.addOnSourceChangedListener(onSourceChangedListener);
    mapChangeDispatcher.onSourceChanged(TEST_STRING);
    verify(onSourceChangedListener).onSourceChangedListener(TEST_STRING);
    verify(onMapChangedListener).onMapChanged(MapView.SOURCE_DID_CHANGE);
    mapChangeDispatcher.removeOnSourceChangedListener(onSourceChangedListener);
    mapChangeDispatcher.onSourceChanged(TEST_STRING);
    verify(onSourceChangedListener).onSourceChangedListener(TEST_STRING);
    verify(onMapChangedListener, times(2)).onMapChanged(MapView.SOURCE_DID_CHANGE);
  }
}