package com.mapbox.mapboxsdk.maps;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/**
 * Class responsible for resolving internal SDK map change events
 */
class MapChangeHandler implements MapView.OnDidFinishLoadingStyleListener,
  MapView.OnDidFinishRenderingFrameListener, MapView.OnDidFinishLoadingMapListener,
  MapView.OnCameraIsChangingListener, MapView.OnCameraDidChangeListener {

  private final List<OnMapReadyCallback> onMapReadyCallbackList = new ArrayList<>();
  private MapboxMap mapboxMap;
  private boolean initialLoad = true;

  void bind(MapboxMap mapboxMap) {
    this.mapboxMap = mapboxMap;
  }

  @Override
  public void onDidFinishLoadingStyle() {
    if (mapboxMap == null) {
      throw new RuntimeException();
    }

    if (initialLoad) {
      initialLoad = false;
      mapboxMap.onPreMapReady();
      onMapReady();
      mapboxMap.onPostMapReady();
    }
  }

  @Override
  public void onDidFinishRenderingFrame(boolean partial) {
    if (mapboxMap == null) {
      return;
    }

    if (partial) {
      mapboxMap.onDidFinishRenderingFrame();
    } else {
      mapboxMap.onDidFinishRenderingFrameFully();
    }
  }

  @Override
  public void onDidFinishLoadingMap() {
    if (mapboxMap == null) {
      return;
    }

    // we require an additional update after the map has finished loading
    // in case an end user action hasn't been invoked at that time
    mapboxMap.onCameraChange();
  }

  @Override
  public void onCameraIsChanging() {
    if (mapboxMap == null) {
      return;
    }
    mapboxMap.onCameraChange();
  }

  @Override
  public void onCameraDidChange(boolean animated) {
    if (mapboxMap != null) {
      return;
    }
    if (animated) {
      mapboxMap.onCameraDidChangeAnimated();
    } else {
      mapboxMap.onCameraChange();
    }
  }

  private void onMapReady() {
    if (onMapReadyCallbackList.size() > 0) {
      // Notify listeners, clear when done
      Iterator<OnMapReadyCallback> iterator = onMapReadyCallbackList.iterator();
      while (iterator.hasNext()) {
        OnMapReadyCallback callback = iterator.next();
        callback.onMapReady(mapboxMap);
        iterator.remove();
      }
    }
  }

  boolean isInitialLoad() {
    return initialLoad;
  }

  void addOnMapReadyCallback(OnMapReadyCallback callback) {
    onMapReadyCallbackList.add(callback);
  }

  void clearOnMapReadyCallbacks() {
    onMapReadyCallbackList.clear();
  }
}
