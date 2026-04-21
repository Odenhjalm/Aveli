from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse

_SOURCE_CONTRACT = "actual_truth/contracts/backend_text_catalog_contract.md"
_STUDIO_LIBRARY_API_SURFACE = "/studio/home-player/library"
_HOME_AUDIO_API_SURFACE = "/home/audio"
_HOME_UPLOAD_API_SURFACE = "/api/home-player/media-assets/upload-url"


def _entry(
    *,
    surface_id: str,
    text_id: str,
    authority_class: str,
    backend_namespace: str,
    api_surface: str,
    render_surface: str,
    value: str,
) -> dict[str, Any]:
    return {
        "surface_id": surface_id,
        "text_id": text_id,
        "authority_class": authority_class,
        "canonical_owner": "backend_text_catalog",
        "source_contract": _SOURCE_CONTRACT,
        "backend_namespace": backend_namespace,
        "api_surface": api_surface,
        "delivery_surface": api_surface,
        "render_surface": render_surface,
        "language": "sv",
        "interpolation_keys": [],
        "forbidden_render_fields": [],
        "value": value,
    }


def build_studio_home_player_text_bundle() -> dict[str, dict[str, Any]]:
    profile_page = "frontend/lib/features/studio/presentation/profile_media_page.dart"
    upload_dialog = "frontend/lib/features/studio/widgets/home_player_upload_dialog.dart"
    upload_routing = "frontend/lib/features/studio/widgets/home_player_upload_routing.dart"
    studio_ns = "backend_text_catalog.studio_editor"
    home_ns = "backend_text_catalog.home"

    entries = [
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_library_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Home-spelarens bibliotek",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_uploads_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ljud för Home-spelaren",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_uploads_description",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value=(
                "Ladda upp ljud direkt för Home-spelaren. Dessa filer är "
                "fristående från kurser. Tar du bort en fil här raderas den helt."
            ),
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_uploads_empty_title",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Inga uppladdningar ännu.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_uploads_empty_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ladda upp ljud som bara ska användas i Home-spelaren.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_links_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Länkat ljud från kurser",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_links_description",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value=(
                "Här ser du ljud som är länkat från kursmaterial. Du kan slå på "
                "eller av länken, eller ta bort den utan att påverka originalfilen.\n"
                "Inga uppladdningar görs här."
            ),
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_links_empty_title",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Inga länkar ännu.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_links_empty_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value=(
                "Länka in ljud från dina kurser. Tar du bort originalfilen blir "
                "länken ogiltig och kan inte spelas."
            ),
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.home_player_link_action",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Länka ljud",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.refresh_action",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Uppdatera",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.retry_action",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Försök igen",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.upload_delete_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ta bort uppladdad fil",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.upload_delete_message",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Filen raderas helt och går inte att ångra.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.upload_delete_action",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ta bort",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.link_delete_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ta bort länk",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.link_delete_message",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Originalfilen i kursen påverkas inte.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.link_delete_action",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ta bort länk",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.cancel_action",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Avbryt",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.audio_kind_label",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ljudfil",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.processing_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Bearbetar ljud...",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.processing_failed_error",
            authority_class="backend_error_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Bearbetningen misslyckades.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.title_required_error",
            authority_class="backend_error_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Filnamn kan inte vara tomt.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.upload_prompt_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Namn på ljudfil",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.upload_prompt_hint",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value='T.ex. "Andningsövning"',
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.upload_ready_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Uppladdning klar.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.link_prompt_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Namn på länkat ljud",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.link_prompt_hint",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value='T.ex. "Meditation kväll"',
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.no_course_audio_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Inga kursljud hittades.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.link_created_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Ljudet har länkats.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.course_picker_title",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Välj kursljud att länka",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.course_picker_search_hint",
            authority_class="contract_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Sök på kurs eller lektion...",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.course_picker_empty_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Inga ljudfiler matchar sökningen.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.course_link_active_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Aktiv",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.course_link_source_missing_error",
            authority_class="backend_error_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Källa saknas",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.course_link_unpublished_status",
            authority_class="backend_status_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Kurs ej publicerad",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.action_failed_error",
            authority_class="backend_error_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Åtgärden kunde inte genomföras. Försök igen.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.load_failed_error",
            authority_class="backend_error_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Biblioteket kunde inte läsas in. Försök igen.",
        ),
        _entry(
            surface_id="TXT-SURF-071",
            text_id="studio_editor.profile_media.auth_failed_error",
            authority_class="backend_error_text",
            backend_namespace=studio_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=profile_page,
            value="Du har inte behörighet att hantera Home-spelaren.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.title",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Lägg till ljud i hemspelaren",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.audio_label",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Ljudfil",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.submit_action",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Ladda upp",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.uploading_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Laddar upp ljud...",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.processing_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Ljudet bearbetas...",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.ready_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Ljudet är redo.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Ljudet kunde inte laddas upp.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.prepare_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Förbereder uppladdning...",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.registering_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Registrerar ljudfil...",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.processing_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Bearbetningen misslyckades.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.refresh_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Kunde inte uppdatera statusen just nu.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.auth_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Du har inte behörighet att hantera uppladdningen i Home-spelaren.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.wait_until_complete_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Vänta tills uppladdningen är klar eller avbryt.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.close_action",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Stäng",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.cancel_action",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Avbryt",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.retry_action",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Försök igen",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.cancelled_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Uppladdningen avbröts.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.audio_only_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Home-spelaren stöder bara ljudfiler.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.start_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Kunde inte starta uppladdningen. Försök igen.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.save_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_dialog,
            value="Kunde inte spara uppladdningen. Försök igen.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.unsupported_audio_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_routing,
            value="Endast WAV, MP3 eller M4A stöds för ljud i Home-spelaren.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.unsupported_video_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_routing,
            value="Home-spelaren stöder bara ljud. Välj en WAV-, MP3- eller M4A-fil.",
        ),
        _entry(
            surface_id="TXT-SURF-075",
            text_id="home.player_upload.unsupported_other_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_STUDIO_LIBRARY_API_SURFACE,
            render_surface=upload_routing,
            value="Välj en WAV-, MP3- eller M4A-fil.",
        ),
    ]
    return {entry["text_id"]: entry for entry in entries}


def build_home_audio_runtime_text_bundle() -> dict[str, dict[str, Any]]:
    runtime_widget = "frontend/lib/features/home/presentation/widgets/home_audio_section.dart"
    home_ns = "backend_text_catalog.home"

    entries = [
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.section_title",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Ljud i Home-spelaren",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.section_description",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Dina uppladdningar och kurslänkar visas här när de är tillgängliga.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.empty_title",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Inget ljud är redo ännu.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.empty_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="När ditt ljud är klart visas det här.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.direct_upload_label",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Ditt ljud",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.course_link_label",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Från kurs",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.pending_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Ljudet förbereds.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.processing_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Ljudet bearbetas.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.ready_status",
            authority_class="backend_status_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Redo att spela",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Ljudet kunde inte spelas upp just nu.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.retry_action",
            authority_class="contract_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Försök igen",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.load_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Home-spelarens ljud kunde inte läsas in. Försök igen.",
        ),
        _entry(
            surface_id="TXT-SURF-076",
            text_id="home.audio.access_failed_error",
            authority_class="backend_error_text",
            backend_namespace=home_ns,
            api_surface=_HOME_AUDIO_API_SURFACE,
            render_surface=runtime_widget,
            value="Du har inte behörighet att öppna Home-spelarens ljud.",
        ),
    ]
    return {entry["text_id"]: entry for entry in entries}


def is_home_player_request(request: Request) -> bool:
    path = request.url.path
    return (
        path == _HOME_AUDIO_API_SURFACE
        or path == _HOME_UPLOAD_API_SURFACE
        or path.startswith("/studio/home-player")
    )


def _error_text_id_for_request(request: Request, status_code: int) -> str:
    path = request.url.path
    method = request.method.upper()
    is_auth_failure = status_code in {401, 403}

    if path == _HOME_AUDIO_API_SURFACE:
        return (
            "home.audio.access_failed_error"
            if is_auth_failure
            else "home.audio.load_failed_error"
        )

    if path == _STUDIO_LIBRARY_API_SURFACE:
        return (
            "studio_editor.profile_media.auth_failed_error"
            if is_auth_failure
            else "studio_editor.profile_media.load_failed_error"
        )

    if path == _HOME_UPLOAD_API_SURFACE:
        return (
            "home.player_upload.auth_failed_error"
            if is_auth_failure
            else "home.player_upload.start_failed_error"
        )

    if path.startswith("/studio/home-player/uploads"):
        if is_auth_failure:
            return "home.player_upload.auth_failed_error"
        if method == "POST":
            return "home.player_upload.save_failed_error"
        return "studio_editor.profile_media.action_failed_error"

    if path.startswith("/studio/home-player/course-links"):
        if is_auth_failure:
            return "studio_editor.profile_media.auth_failed_error"
        return "studio_editor.profile_media.action_failed_error"

    return "studio_editor.profile_media.action_failed_error"


_ERROR_CODE_BY_TEXT_ID = {
    "studio_editor.profile_media.load_failed_error": "home_player_library_load_failed",
    "studio_editor.profile_media.auth_failed_error": "home_player_auth_failed",
    "studio_editor.profile_media.action_failed_error": "home_player_action_failed",
    "home.player_upload.start_failed_error": "home_player_upload_start_failed",
    "home.player_upload.save_failed_error": "home_player_upload_save_failed",
    "home.player_upload.auth_failed_error": "home_player_upload_auth_failed",
    "home.audio.load_failed_error": "home_audio_load_failed",
    "home.audio.access_failed_error": "home_audio_access_failed",
}


def _lookup_text_entry(text_id: str) -> dict[str, Any]:
    for bundle_builder in (
        build_studio_home_player_text_bundle,
        build_home_audio_runtime_text_bundle,
    ):
        bundle = bundle_builder()
        entry = bundle.get(text_id)
        if entry is not None:
            return entry
    raise KeyError(f"Unknown Home Player text id: {text_id}")


def canonical_home_player_error_response(
    *,
    request: Request,
    status_code: int,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    text_id = _error_text_id_for_request(request, status_code)
    entry = _lookup_text_entry(text_id)
    normalized_status = status_code if status_code in {400, 401, 403, 404, 422, 500} else 500
    return JSONResponse(
        status_code=normalized_status,
        content={
            "status": "error",
            "error_code": _ERROR_CODE_BY_TEXT_ID[text_id],
            "message": entry["value"],
        },
        headers=headers,
    )


def home_player_validation_error_response(
    *,
    request: Request,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    return canonical_home_player_error_response(
        request=request,
        status_code=422,
        headers=headers,
    )
