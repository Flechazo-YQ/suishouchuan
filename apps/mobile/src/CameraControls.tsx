import React, {useEffect, useRef, useState} from 'react';
import {Animated, Easing, PanResponder, Pressable, StyleSheet, Text, View, useWindowDimensions} from 'react-native';

const tabWidth = 84;

export function useCaptureModeMotion(batch: boolean, locked: boolean, onChange: (batch: boolean) => void) {
  const {width} = useWindowDimensions();
  const offset = useRef(new Animated.Value(0)).current;
  const progress = useRef(new Animated.Value(batch ? 1 : 0)).current;
  const moving = useRef(false);
  const [transitioning, setTransitioning] = useState(false);
  const current = useRef({batch, locked, onChange, width});
  current.current = {batch, locked, onChange, width};

  useEffect(() => {
    Animated.timing(progress, {toValue: batch ? 1 : 0, duration: 240, easing: Easing.out(Easing.cubic), useNativeDriver: true}).start();
  }, [batch, progress]);
  useEffect(() => {
    if (locked) {offset.stopAnimation(); offset.setValue(0); moving.current = false; setTransitioning(false);}
  }, [locked, offset]);
  useEffect(() => () => {offset.stopAnimation(); progress.stopAnimation();}, [offset, progress]);

  function settle() {Animated.spring(offset, {toValue: 0, speed: 24, bounciness: 0, useNativeDriver: true}).start();}
  function selectMode(next: boolean) {
    const value = current.current;
    if (value.locked || moving.current || value.batch === next) {if (!moving.current) settle(); return;}
    moving.current = true; setTransitioning(true);
    const direction = next ? -1 : 1;
    Animated.timing(offset, {toValue: direction * value.width, duration: 130, easing: Easing.in(Easing.quad), useNativeDriver: true}).start(({finished}) => {
      if (!finished || current.current.locked) {moving.current = false; setTransitioning(false); return;}
      current.current.onChange(next);
      // Keep one native camera session alive while its two capture modes slide across the viewport.
      offset.setValue(-direction * current.current.width);
      Animated.timing(offset, {toValue: 0, duration: 190, easing: Easing.out(Easing.cubic), useNativeDriver: true}).start(() => {
        moving.current = false; setTransitioning(false);
      });
    });
  }
  const select = useRef(selectMode); select.current = selectMode;
  const responder = useRef(PanResponder.create({
    onMoveShouldSetPanResponder: (_, gesture) => !current.current.locked && !moving.current && Math.abs(gesture.dx) > 14 && Math.abs(gesture.dx) > Math.abs(gesture.dy) * 1.5,
    onPanResponderMove: (_, gesture) => {
      if (current.current.locked || moving.current) return;
      const allowedDirection = current.current.batch ? gesture.dx > 0 : gesture.dx < 0;
      offset.setValue(allowedDirection ? Math.max(-current.current.width, Math.min(current.current.width, gesture.dx)) : gesture.dx * .12);
    },
    onPanResponderRelease: (_, gesture) => {
      if (Math.abs(gesture.dx) > 55 || (Math.abs(gesture.dx) > 20 && Math.abs(gesture.vx) > .5)) select.current(gesture.dx < 0);
      else settle();
    },
    onPanResponderTerminate: settle,
    onPanResponderTerminationRequest: () => false,
  })).current;
  return {panHandlers: responder.panHandlers, pageStyle: {transform: [{translateX: offset}]}, progress, selectMode, transitioning};
}

export function CaptureModeTabs({batch, disabled, progress, onSelect}: {
  batch: boolean; disabled: boolean; progress: Animated.Value; onSelect: (batch: boolean) => void;
}) {
  return <View style={c.tabs} accessibilityRole="tablist">
    <Animated.View pointerEvents="none" style={[c.selectedTab, {transform: [{translateX: progress.interpolate({inputRange: [0, 1], outputRange: [0, tabWidth]})}]}]}/>
    {['拍摄', '连拍'].map((label, index) => <Pressable key={label} style={c.tab} disabled={disabled} onPress={() => onSelect(index === 1)}
      accessibilityRole="tab" accessibilityLabel={label + '模式'} accessibilityState={{selected: batch === (index === 1), disabled}}>
      <Text style={[c.tabText, batch === (index === 1) && c.activeText]}>{label}</Text>
    </Pressable>)}
  </View>;
}

export function GalleryButton({disabled, onPress}: {disabled: boolean; onPress: () => void}) {
  return <Pressable onPress={onPress} disabled={disabled} style={({pressed}) => [c.sideButton, (disabled || pressed) && c.dim]}
    accessibilityRole="button" accessibilityLabel="打开相册，多选照片">
    <View style={c.iconBox}>
      <View style={c.albumBack}/>
      <View style={c.album}><View style={c.sun}/><View style={c.mountain}/><View style={c.smallMountain}/></View>
    </View>
    <Text style={c.toolLabel}>相册</Text>
  </Pressable>;
}

export function ScreenCaptureButton({disabled, onPress}: {disabled: boolean; onPress: () => void}) {
  return <Pressable onPress={onPress} disabled={disabled} style={({pressed}) => [c.sideButton, (disabled || pressed) && c.dim]}
    accessibilityRole="button" accessibilityLabel="截屏和录屏">
    <View style={c.iconBox}>
      <View style={c.screen}><View style={c.screenLine}/><View style={c.screenDot}/></View>
    </View>
    <Text style={c.toolLabel}>截屏 / 录屏</Text>
  </Pressable>;
}

const c = StyleSheet.create({
  tabs: {padding: 3, flexDirection: 'row', borderRadius: 25, backgroundColor: '#181b17'},
  selectedTab: {position: 'absolute', left: 3, top: 3, bottom: 3, width: tabWidth, borderRadius: 22, backgroundColor: '#323b23'},
  tab: {width: tabWidth, minHeight: 44, alignItems: 'center', justifyContent: 'center'},
  tabText: {color: '#b2b8ad', fontSize: 14, fontWeight: '600'}, activeText: {color: '#d9f278'},
  sideButton: {width: 92, minHeight: 68, justifyContent: 'center', alignItems: 'center', gap: 4},
  iconBox: {width: 44, height: 36, justifyContent: 'center', alignItems: 'center'}, dim: {opacity: .45},
  albumBack: {position: 'absolute', width: 29, height: 29, borderWidth: 1.5, borderColor: '#888', borderRadius: 6, transform: [{rotate: '-9deg'}, {translateX: -3}, {translateY: -3}]},
  album: {width: 32, height: 32, borderRadius: 6, borderWidth: 1.8, borderColor: '#eee', backgroundColor: '#141414', overflow: 'hidden'},
  sun: {position: 'absolute', right: 5, top: 5, width: 5, height: 5, borderRadius: 3, backgroundColor: '#eee'},
  mountain: {position: 'absolute', width: 22, height: 22, left: -2, bottom: -11, borderRadius: 2, backgroundColor: '#ddd', transform: [{rotate: '45deg'}]},
  smallMountain: {position: 'absolute', width: 16, height: 16, right: -3, bottom: -7, borderRadius: 2, backgroundColor: '#aaa', transform: [{rotate: '45deg'}]},
  screen: {width: 30, height: 23, borderWidth: 1.8, borderRadius: 5, borderColor: '#eee'},
  screenLine: {position: 'absolute', width: 11, height: 1.5, left: 4, top: 6, backgroundColor: '#ddd'},
  screenDot: {position: 'absolute', right: -5, bottom: -5, width: 12, height: 12, borderRadius: 6, backgroundColor: '#d9f278', borderWidth: 3, borderColor: '#050505'},
  toolLabel: {fontSize: 12, color: '#e2e6dc', fontWeight: '500', textAlign: 'center'},
});
