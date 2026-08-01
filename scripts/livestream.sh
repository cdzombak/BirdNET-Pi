#!/usr/bin/env bash
# Live Audio Stream Service Script
source /etc/birdnet/birdnet.conf

# Read the logging level from the configuration option
LOGGING_LEVEL="${LogLevel_LiveAudioStreamService}"
# If empty for some reason default to log level of error
[ -z $LOGGING_LEVEL ] && LOGGING_LEVEL='error'
# Additionally if we're at debug or info level then allow printing of script commands and variables
if [ "$LOGGING_LEVEL" == "info" ] || [ "$LOGGING_LEVEL" == "debug" ];then
  # Enable printing of commands/variables etc to terminal for debugging
  set -x
fi

# Live capture (both ALSA and RTSP) occasionally delivers a packet whose
# timestamp is not greater than its predecessor. The mp3 muxer rejects each one
# with "Application provided invalid, non monotonically increasing dts to muxer"
# at AV_LOG_ERROR, so it is not suppressible via the log level offered in the
# UI. On a quiet host this was ~0.8 messages/second, roughly half of all system
# log volume.
#
# aresample emits on its own sample-counted timeline, so its output timestamps
# are monotonic by construction. async=1 is the lowest non-zero setting: it
# permits only filling and trimming, never the stretching/squeezing that values
# >1 enable, so it cannot alter pitch or tempo. Compensation is additionally
# gated by min_hard_comp (default 0.1s), and observed jitter here is far below
# that -- measured over 45s at -loglevel verbose, zero compensation events
# occurred and the sample rate was unchanged (48000 -> 48000).
AFILTER='aresample=async=1'
if [ "$ACTIVATE_FREQSHIFT_IN_LIVESTREAM" == "true" ]; then
  # Both filters must share a single -af: a second -af replaces the first
  # rather than chaining, so specifying them separately would silently drop one.
  AFILTER='rubberband=pitch='${FREQSHIFT_LO}'/'${FREQSHIFT_HI}",${AFILTER}"
fi
AFILTER_OPT="-af ${AFILTER}"

if [ -z ${REC_CARD} ];then
  echo "Stream not supported"
elif [[ ! -z ${RTSP_STREAM} ]];then
  # Explode the RSPT steam setting into an array so we can count the number we have
  RSTP_STREAMS_EXPLODED_ARRAY=(${RTSP_STREAM//,/ })

  # If for some reason the RTSP_STREAM_TO_LIVESTREAM is not set, then init it to 0 to use the first stream
  if [[ -z ${RTSP_STREAM_TO_LIVESTREAM} ]];then
    RTSP_STREAM_TO_LIVESTREAM=0
  fi

  # Get the RSTP stream at the specified array index
  SELECTED_RSTP_STREAM=${RSTP_STREAMS_EXPLODED_ARRAY[RTSP_STREAM_TO_LIVESTREAM]}

  # If for some reason the RTSP stream url is null
  if [[ -z ${SELECTED_RSTP_STREAM} ]];then
    # Try select the first stream
    SELECTED_RSTP_STREAM=${RSTP_STREAMS_EXPLODED_ARRAY[0]}
  fi

  ffmpeg -nostdin -loglevel $LOGGING_LEVEL -ac ${CHANNELS} -i ${SELECTED_RSTP_STREAM} -acodec libmp3lame \
    -b:a 320k -ac ${CHANNELS} -content_type 'audio/mpeg' \
    ${AFILTER_OPT} \
    -f mp3 icecast://source:${ICE_PWD}@localhost:8000/stream -re
else
	ffmpeg -nostdin -loglevel $LOGGING_LEVEL -ac ${CHANNELS} -f alsa -i ${REC_CARD} -acodec libmp3lame \
    -b:a 320k -ac ${CHANNELS} -content_type 'audio/mpeg' \
    ${AFILTER_OPT} \
    -f mp3 icecast://source:${ICE_PWD}@localhost:8000/stream -re
fi
