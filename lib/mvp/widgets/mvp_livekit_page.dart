import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../mvp/api_client.dart';

class MvpLiveKitPage extends StatefulWidget {
  const MvpLiveKitPage({super.key, required this.client});

  final MvpApiClient client;

  @override
  State<MvpLiveKitPage> createState() => _MvpLiveKitPageState();
}

class _MvpLiveKitPageState extends State<MvpLiveKitPage> {
  final _seminarId = TextEditingController();
  Room? _room;
  CancelListenFunc? _roomDisconnectedCancel;
  bool _connecting = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _seminarId.dispose();
    _roomDisconnectedCancel?.call();
    _room?.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_seminarId.text.isEmpty) {
      setState(() => _error = 'Ange seminariets UUID');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
      _status = 'Hämtar token...';
    });
    try {
      final payload = await widget.client.requestLiveKitToken(_seminarId.text.trim());
      _status = 'Ansluter till LiveKit...';
      await LiveKitClient.initialize();
      final room = Room(roomOptions: const RoomOptions());
      await room.connect(payload.wsUrl, payload.token);
      _roomDisconnectedCancel?.call();
      _roomDisconnectedCancel = room.events.on<RoomDisconnectedEvent>((_) {
        _roomDisconnectedCancel?.call();
        _roomDisconnectedCancel = null;
        if (mounted) {
          setState(() {
            _room = null;
            _status = 'Frånkopplad';
          });
        }
      });
      setState(() {
        _room = room;
        _status = 'Ansluten som ${room.localParticipant?.identity ?? 'okänd'}';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    _roomDisconnectedCancel?.call();
    _roomDisconnectedCancel = null;
    await _room?.disconnect();
    if (!mounted) {
      return;
    }
    setState(() {
      _room = null;
      _status = 'Frånkopplad';
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final participants = <Participant<dynamic>>[];
    if (room != null) {
      final localParticipant = room.localParticipant;
      if (localParticipant != null) {
        participants.add(localParticipant);
      }
      participants.addAll(room.remoteParticipants.values);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LiveKit snabbtest'),
          const SizedBox(height: 12),
          TextField(
            controller: _seminarId,
            decoration: const InputDecoration(labelText: 'Seminarie-ID (uuid)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _connecting ? null : _connect,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Anslut'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: room == null ? null : _disconnect,
                child: const Text('Koppla från'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_status != null) Text(_status!),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: participants.isEmpty
                ? const Center(child: Text('Inga deltagare'))
                : ListView.builder(
                    itemCount: participants.length,
                    itemBuilder: (context, index) {
                      final participant = participants[index];
                      final isLocalParticipant = participant is LocalParticipant;
                      return ListTile(
                        leading: Icon(isLocalParticipant ? Icons.person : Icons.person_outline),
                        title: Text(participant.identity),
                        subtitle: Text('Audio: ${participant.isMuted ? 'muted' : 'live'}'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
