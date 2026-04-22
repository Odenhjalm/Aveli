Map<String, dynamic> sampleAdminSettingsPayload() => {
  'metrics': {
    'total_users': 42,
    'total_teachers': 7,
    'total_courses': 12,
    'published_courses': 9,
    'paid_orders_total': 33,
    'paid_orders_30d': 8,
    'paying_customers_total': 19,
    'paying_customers_30d': 5,
    'revenue_total_cents': 245000,
    'revenue_30d_cents': 82000,
    'login_events_7d': 63,
    'active_users_7d': 18,
  },
  'priorities': [
    {
      'teacher_id': 'teacher-1',
      'display_name': 'Aveli Teacher',
      'email': 'teacher-1@example.com',
      'priority': 1,
      'notes': 'Needs review before launch.',
      'total_courses': 3,
      'published_courses': 1,
      'updated_at': '2026-04-21T10:00:00Z',
      'updated_by': 'admin-1',
      'updated_by_name': 'Admin One',
    },
    {
      'teacher_id': 'teacher-2',
      'display_name': 'Library Curator',
      'email': 'teacher-2@example.com',
      'priority': 2,
      'notes': 'Publishing queue.',
      'total_courses': 2,
      'published_courses': 2,
      'updated_at': '2026-04-20T09:00:00Z',
      'updated_by': 'admin-1',
      'updated_by_name': 'Admin One',
    },
  ],
};

Map<String, dynamic> sampleMediaHealthPayload() => {
  'control_plane': 'media',
  'status': 'ok',
  'access': 'admin_only',
  'workspace': 'observatorium',
  'viewer_id': 'admin-1',
  'checked_at': '2026-04-22T08:30:00Z',
  'capabilities': [
    {'id': 'uploads', 'label': 'Direct uploads', 'status': 'ready'},
    {'id': 'diagnostics', 'label': 'Diagnostics', 'status': 'ready'},
  ],
  'actions': [
    {
      'id': 'media-dashboard',
      'label': 'Open media control',
      'route': '/admin/media-control',
    },
    {
      'id': 'admin-system',
      'label': 'Open system page',
      'route': '/admin/settings',
    },
  ],
};
