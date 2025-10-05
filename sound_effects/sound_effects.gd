class_name SoundEffects extends Node

@onready
var audio_stream_players : Array[AudioStreamPlayer] = [
	$AudioStreamPlayer, $AudioStreamPlayer2, $AudioStreamPlayer3
]
	
func play_random_sound():
	# 随机选择一个 AudioStreamPlayer 播放声音
	for player in audio_stream_players:
		if not player.playing:
			player.play()
			return
	# 如果都在播放，选择第一个强制播放
	audio_stream_players[0].stop()
	audio_stream_players[0].play()
	pass
