# OBS Dropped Frame Alarm

[OBS Lua Script](https://obsproject.com/docs/scripting.html) which plays a audio alarm (media source) when [OBS Studio](https://obsproject.com/) dropped frames are detected, and draws a graph of recent dropped frames.

## Requirements

- [OBS Studio](https://obsproject.com/)

## Incompatabilites

[OBS-Websockets connections will be disrupted when the alarm activates.](https://obsproject.com/forum/threads/making-a-source-visible-from-a-script-timer-stops-obs-websocket-updates.83140/)

## Usage

Add a media source for the alarm. A suitable sound file is provided with the script. Open Advanced Audio Properties for the source and change Audio Monitoring to Monitor Only (mute output).

Add a copy of the alarm source to every scene where you want to hear it.

You may configure the sample window for alarms, as well as the percent of dropped frames to alarm at.

A custom source is available for drawing a dropped frame graph in the sample period. It can be added to the source panel. You may want to hide it and use a windowed projector to view the graph yourself. Yellow shows congestion, red shows fraction of dropped frames.

## Credits

Alert sounds: [`pup_alert.mp3`](https://freesound.org/people/willy_ineedthatapp_com/sounds/167337/) by `willy_ineedthatapp_com`
