// MasterofDeath's Editing Script
{
    function masterOfDeathUI(thisObj) {
        var win = (thisObj instanceof Panel)
            ? thisObj
            : new Window("palette", "MasterofDeath Editing Helper", undefined, { resizeable: true });

        // UI resource string
        var res =
        "group { \
            orientation:'column', alignment:['fill','top'], alignChildren:['fill','top'], spacing:5, \
            cutBtn: Button { text:'Cut Marker', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'First select the layer with markers, then the layer you want to cut. If you want to use the composition markers, only select the layer you want to' }, \
            wfBtn: Button { text:'White Flash', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Left Click to create a White Flash. Shift + Click to create White Flash 2.' }, \
            mirrorBtn: Button { text:'Mirror Edges', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Applies Motion Tile and mirrors edges for head tracked footage.' }, \
            deleteTrackBtn: Button { text:'Delete Tracking', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Removes all Motion Trackers and resets Anchor Point keyframes.' }, \
            fitBtn: Button { text:'Fit to Comp', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Left Click to Fit to Comp Height. Shift + Left Click to Fit to Comp Width.' }, \
            fadeBtn: Button { text:'Fade out', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Fades out a layer using Gaussian Blur and Opacity Keyframes.' }, \
            frameBlendBtn: Button { text:'Frame Blending', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Applies the Twixtor Pro effect to interpolate frames.' }, \
            expandTextBtn: Button { text:'Expand Text', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Adds Increase Tracking Keyframes to text layers.' }, \
            fadeUpWordsBtn: Button { text:'Fade up words', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Applies the Fade Up Words effect and adds keyframes after every single word.' }, \
            precompBtn: Button { text:'Precomp', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Precomposes each selected layer individually and names them numerically.' },\
            muffleAudioBtn: Button { text:'Muffle Audio', alignment:['fill','top'], maximumSize:[1000,30], helpTip:'Muffles and Fades out the audio.' }\
        }";
        

        // attach UI
        win.grp = win.add(res);

        // ---------------- BUTTON FUNCTIONS ----------------

        // Fade up words
        win.grp.muffleAudioBtn.onClick = function () {
            app.beginUndoGroup("Muffle Audio");
            var comp = app.project.activeItem;
            if (!comp || !(comp instanceof CompItem)) {
                alert("Please open a composition.");
                app.endUndoGroup();
                return;
            }

            var layers = comp.selectedLayers;
            if (layers.length === 0) {
                alert("Please select at least one layer.");
                app.endUndoGroup();
                return;
            }

            var presetFile = File("/Users/masterofdeath/Documents/Adobe/After Effects 2025/User Presets/Random Presets/Muffled Audio.ffx");
            if (!presetFile.exists) {
                alert("Preset not found:\n" + decodeURI(presetFile.fsName));
                app.endUndoGroup();
                return;
            }

            var currentTime = comp.time;
            var frameOffset = 77 / comp.frameRate;

            for (var i = 0; i < layers.length; i++) {
                var layer = layers[i];
                layer.applyPreset(presetFile);

                var audioLevels = layer.property("Audio").property("Audio Levels");
                if (audioLevels) {
                    audioLevels.setValueAtTime(currentTime, [-10, -10]);
                    audioLevels.setValueAtTime(currentTime + frameOffset, [-15, -15]);
                }
            }

        };
        win.grp.fadeUpWordsBtn.onClick = function () {
            var comp = app.project.activeItem;
            if (!(comp && comp instanceof CompItem)) {
                alert("Please select a composition.");
                return;
            }

            var selectedLayer = comp.selectedLayers[0];
            if (!selectedLayer || !(selectedLayer.property("Source Text"))) {
                alert("Please select a text layer.");
                return;
            }

            app.beginUndoGroup("Fade Up Words Keyframe Helper");

            var presetPath = "/Applications/Adobe After Effects 2025/Presets/Text/Animate In/Fade Up Words.ffx";
            selectedLayer.applyPreset(new File(presetPath));

            var animators = selectedLayer.property("Text").property("Animators");
            var rangeSelector = null;

            for (var i = 1; i <= animators.numProperties; i++) {
                var animator = animators.property(i);
                if (animator && animator.matchName === "ADBE Text Animator") {
                    rangeSelector = animator.property("Selectors").property("Range Selector 1");
                    break;
                }
            }

            if (!rangeSelector) {
                alert("Could not find range selector.");
                app.endUndoGroup();
                return;
            }

            var startProp = rangeSelector.property("Start");
            if (startProp.numKeys < 2) {
                alert("Expected 2 keyframes on Start.");
                app.endUndoGroup();
                return;
            }

            var t1 = startProp.keyTime(1);
            var t2 = startProp.keyTime(2);
            var v1 = startProp.keyValue(1);
            var v2 = startProp.keyValue(2);

            var text = selectedLayer.property("Source Text").value.text;
            var words = text.match(/\S+/g);
            if (!words || words.length < 2) {
                alert("Need at least two words.");
                app.endUndoGroup();
                return;
            }

            var wordCount = words.length;

            for (var i = 1; i < wordCount; i++) {
                var ratio = i / wordCount;
                var t = t1 + (t2 - t1) * ratio;
                var val = v1 + (v2 - v1) * ratio;

                if (!startProp.isTimeVarying) {
                    startProp.setValueAtTime(t, val);
                } else {
                    startProp.setValueAtTime(t, startProp.valueAtTime(t, false));
                }
            }

            app.endUndoGroup();
        };

        // Delete tracking
        win.grp.deleteTrackBtn.onClick = function () {
            app.beginUndoGroup("Delete Tracking and Reset Anchor Point");
            var comp = app.project.activeItem;
            if (!comp || !(comp instanceof CompItem)) {
                alert("Please open a composition.");
                return;
            }
            var layers = comp.selectedLayers;
            for (var i = 0; i < layers.length; i++) {
                var layer = layers[i];

                if (layer.motionTrackers && layer.motionTrackers.numProperties > 0) {
                    for (var t = layer.motionTrackers.numProperties; t >= 1; t--) {
                        layer.motionTrackers.property(t).remove();
                    }
                }

                var anchor = layer.property("Transform").property("Anchor Point");
                if (anchor && anchor.numKeys > 0) {
                    for (var k = anchor.numKeys; k >= 1; k--) {
                        anchor.removeKey(k);
                    }
                }

                anchor.setValue([layer.width / 2, layer.height / 2]);
            }
            app.endUndoGroup();
        };

        // Precomp
        win.grp.precompBtn.onClick = function () {
            var comp = app.project.activeItem;
            if (!(comp instanceof CompItem)) {
                alert("Please select a composition.");
                return;
            }

            if (comp.selectedLayers.length === 0) {
                alert("Please select at least one layer.");
                return;
            }

            app.beginUndoGroup("Precompose Each Layer Individually");

            var selectedLayers = comp.selectedLayers.slice();
            var counter = 1;

            for (var i = 0; i < selectedLayers.length; i++) {
                var layer = selectedLayers[i];
                var layerIndex = layer.index;

                for (var j = 1; j <= comp.numLayers; j++) {
                    comp.layer(j).selected = false;
                }

                comp.layer(layerIndex).selected = true;

                var name = counter.toString();

                var inPoint = layer.inPoint;
                var outPoint = layer.outPoint;
                var duration = outPoint - inPoint;

                var precompName = name;
                var precomp = comp.layers.precompose([layerIndex], precompName, true);
                var precompLayer = comp.selectedLayers[0];

                var nestedComp = precompLayer.source;
                for (var k = 1; k <= nestedComp.numLayers; k++) {
                    nestedComp.layer(k).startTime -= inPoint;
                }

                nestedComp.duration = duration;

                precompLayer.startTime = inPoint;
                precompLayer.inPoint = inPoint;
                precompLayer.outPoint = outPoint;

                counter++;
            }

            app.endUndoGroup();
        };

        // Cut markers
        win.grp.cutBtn.onClick = function () {
            app.beginUndoGroup("Split Layer at Markers");

            var comp = app.project.activeItem;
            if (!(comp && comp instanceof CompItem)) {
                alert("Please open a composition.");
                return;
            }

            var selectedLayers = comp.selectedLayers;
            var markerTimes = [];
            var targetLayer;

            if (selectedLayers.length === 1) {
                targetLayer = selectedLayers[0];

                if (comp.markerProperty && comp.markerProperty.numKeys > 0) {
                    for (var i = 1; i <= comp.markerProperty.numKeys; i++) {
                        markerTimes.push(comp.markerProperty.keyTime(i));
                    }
                } else {
                    alert("No markers found on the composition.");
                    app.endUndoGroup();
                    return;
                }
            } else if (selectedLayers.length === 2) {
                var markerLayer = selectedLayers[0];
                targetLayer = selectedLayers[1];

                if (markerLayer.property("Marker") && markerLayer.property("Marker").numKeys > 0) {
                    for (var i = 1; i <= markerLayer.property("Marker").numKeys; i++) {
                        markerTimes.push(markerLayer.property("Marker").keyTime(i));
                    }
                } else {
                    alert("The first selected layer has no markers.");
                    app.endUndoGroup();
                    return;
                }
            } else {
                alert("Please select one or two layers:\n• One layer to split (uses comp markers)\n• Or two layers: Marker Layer + Layer to Split");
                app.endUndoGroup();
                return;
            }

            markerTimes.sort(function(a, b) { return a - b; });
            for (var j = markerTimes.length - 1; j >= 0; j--) {
                var time = markerTimes[j];
                if (time > targetLayer.inPoint && time < targetLayer.outPoint) {
                    targetLayer.splitLayer(time);
                }
            }

            app.endUndoGroup();
        };

        // White flash
        win.grp.wfBtn.addEventListener("mousedown", function(event) {
            app.beginUndoGroup("White Flash");
            var comp = app.project.activeItem;
            if (!comp || !(comp instanceof CompItem)) {
                alert("Please open a composition.");
                return;
            }

            var isShift = ScriptUI.environment.keyboardState.shiftKey;
            var presetFile = isShift
                ? File("~/Documents/Adobe/After Effects 2025/User Presets/Random Presets/White Flash 2.ffx")
                : File("~/Documents/Adobe/After Effects 2025/User Presets/Random Presets/White Flash.ffx");

            if (!presetFile.exists) {
                alert("Preset not found:\n" + decodeURI(presetFile.fsName));
                return;
            }

            var solid = comp.layers.addSolid([1, 1, 1], "White Flash", comp.width, comp.height, comp.pixelAspect, comp.duration);
            solid.applyPreset(presetFile);

            var keyTimes = [];
            function collectKeyTimes(prop) {
                if (prop.canVaryOverTime && prop.numKeys > 0) {
                    for (var i = 1; i <= prop.numKeys; i++) {
                        var t = prop.keyTime(i);
                        if (keyTimes.indexOf(t) === -1) keyTimes.push(t);
                    }
                }
                if (prop.numProperties > 0) {
                    for (var i = 1; i <= prop.numProperties; i++) {
                        collectKeyTimes(prop.property(i));
                    }
                }
            }

            collectKeyTimes(solid);
            if (keyTimes.length === 0) {
                alert("No keyframes found in the applied preset.");
                solid.remove();
                return;
            }

            keyTimes.sort(function(a, b) { return a - b; });

            var markerProp = solid.property("Marker");
            for (var i = 0; i < keyTimes.length; i++) {
                var marker = new MarkerValue("");
                markerProp.setValueAtTime(keyTimes[i], marker);
            }

            var firstKey = keyTimes[0];
            var lastKey = keyTimes[keyTimes.length - 1];
            var frameOffset = isShift ? (28 / comp.frameRate) : 0;
            if (isShift) {
                solid.startTime -= frameOffset;
                firstKey -= frameOffset;
                lastKey  -= frameOffset;
            }

            solid.inPoint = firstKey;
            solid.outPoint = lastKey;

            app.endUndoGroup();
        });

        // Mirror edges
        win.grp.mirrorBtn.onClick = function () {
            app.beginUndoGroup("Mirror Edges");
            var comp = app.project.activeItem;
            var layers = comp.selectedLayers;
            if (!comp || !(comp instanceof CompItem) || layers.length === 0) {
                alert("Please open a composition and select at least one layer.");
                return;
            }
            for (var i = 0; i < layers.length; i++) {
                var layer = layers[i];
                var effect = layer.property("Effects").addProperty("Motion Tile");
                if (effect) {
                    effect.property("Output Width").setValue(400);
                    effect.property("Output Height").setValue(400);
                    effect.property("Mirror Edges").setValue(true);
                }
            }
            app.endUndoGroup();
        };

        // Fit to comp
        win.grp.fitBtn.addEventListener("mousedown", function(event) {
            app.beginUndoGroup("Fit to Comp");
            var comp = app.project.activeItem;
            if (!comp || !(comp instanceof CompItem)) {
                alert("Please open a composition.");
                return;
            }

            var isShift = ScriptUI.environment.keyboardState.shiftKey;
            var layers = comp.selectedLayers;

            for (var i = 0; i < layers.length; i++) {
                var layer = layers[i];
                var scale = layer.property("Transform").property("Scale");
                var position = layer.property("Transform").property("Position");
                var anchor = layer.property("Transform").property("Anchor Point");

                var widthRatio = comp.width / layer.width;
                var heightRatio = comp.height / layer.height;
                var newScale = isShift ? widthRatio : heightRatio;

                scale.setValue([100 * newScale, 100 * newScale]);

                var centeredPos = [ comp.width / 2, comp.height / 2 ];
                position.setValue(centeredPos);
            }

            app.endUndoGroup();
        });

        // Fade out
        win.grp.fadeBtn.addEventListener("mousedown", function (event) {
            app.beginUndoGroup("Fade Out");
            var comp = app.project.activeItem;
            if (!comp || !(comp instanceof CompItem)) {
                alert("Please open a composition.");
                app.endUndoGroup();
                return;
            }

            var isShift = ScriptUI.environment.keyboardState.shiftKey;
            var presetFile = File("~/Documents/Adobe/After Effects 2025/User Presets/Random Presets/Fade out text.ffx");
            var layers = comp.selectedLayers;

            for (var i = 0; i < layers.length; i++) {
                var layer = layers[i];
                layer.applyPreset(presetFile);

                if (isShift) {
                    reverseAllKeyframes(layer);
                }
            }

            app.endUndoGroup();

            function reverseAllKeyframes(layer) {
                var allProps = [];

                function collectProps(propGroup) {
                    if (!propGroup) return;
                    if (propGroup.numProperties > 0) {
                        for (var i = 1; i <= propGroup.numProperties; i++) {
                            collectProps(propGroup.property(i));
                        }
                    } else if (propGroup.canVaryOverTime && propGroup.numKeys > 1) {
                        allProps.push(propGroup);
                    }
                }

                collectProps(layer.property("Transform"));
                collectProps(layer.property("Effects"));

                for (var j = 0; j < allProps.length; j++) {
                    var prop = allProps[j];
                    var numKeys = prop.numKeys;
                    var times = [], values = [];

                    for (var k = 1; k <= numKeys; k++) {
                        times.push(prop.keyTime(k));
                        values.push(prop.keyValue(k));
                    }

                    var minTime = Math.min.apply(null, times);
                    var maxTime = Math.max.apply(null, times);

                    for (var k = numKeys; k >= 1; k--) {
                        prop.removeKey(k);
                    }

                    for (var k = 0; k < times.length; k++) {
                        var reversedTime = maxTime - (times[k] - minTime);
                        prop.setValueAtTime(reversedTime, values[k]);
                    }
                }
            }
        });

        // Frame blending
        win.grp.frameBlendBtn.onClick = function () {
            app.beginUndoGroup("Frame Blending");
            var comp = app.project.activeItem;
            var presetFile = File("~/Documents/Adobe/After Effects 2025/User Presets/Random Presets/Smooth 60fps.ffx");
            var layers = comp.selectedLayers;
            for (var i = 0; i < layers.length; i++) {
                layers[i].applyPreset(presetFile);
            }
            app.endUndoGroup();
        };

        // Expand text
        win.grp.expandTextBtn.onClick = function () {
            app.beginUndoGroup("Expand Text");
            var comp = app.project.activeItem;
            var presetFile = File("~/Documents/Adobe/After Effects 2025/User Presets/Texts/Expanding Text Animation.ffx");
            var layers = comp.selectedLayers;
            for (var i = 0; i < layers.length; i++) {
                layers[i].applyPreset(presetFile);
            }
            app.endUndoGroup();
        };

        // ---------------- INIT WINDOW ----------------
        if (win instanceof Window) {
            win.center();
            win.show();
        } else {
            win.layout.layout(true);
            win.layout.resize();
        }

        win.onResizing = win.onResize = function () { this.layout.resize(); };

        return win;
    }

    
    masterOfDeathUI(this);
}